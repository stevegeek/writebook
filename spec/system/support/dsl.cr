# Rails-style DSL on top of LuckyFlow. Re-exports the most-used Capybara-isms
# (`fill_in`, `click_on`, `assert_text`, etc.) so ported Rails system tests
# read close to the originals.
#
# Crystal Spec runs `it` blocks at the top level (no implicit instance method
# scope), so these are defined as top-level free functions. State is held in
# the LuckyFlow registry singleton.

# Cached per-spec LuckyFlow wrapper. `LuckyFlow.new` is cheap (the underlying
# driver is registry-singleton), so re-using one per example is plenty.
module SystemSpec::DSLState
  @@flow : LuckyFlow? = nil

  def self.flow : LuckyFlow
    @@flow ||= LuckyFlow.new
  end

  def self.reset : Nil
    @@flow = nil
  end
end

def __lucky_flow : LuckyFlow
  SystemSpec::DSLState.flow
end

# Reset the wrapper between specs (LuckyFlow.reset is invoked by its own
# around-each, but the wrapper closes over the previous driver instance).
Spec.before_each { SystemSpec::DSLState.reset }

# ---------------- navigation ----------------

def visit(path : String) : Nil
  __lucky_flow.visit(path)
end

def current_path : String
  URI.parse(LuckyFlow.driver.current_url).path
end

# ---------------- form input ----------------

# `fill_in "Email", with: "x@y"` — locates by label, name attr, or id.
def fill_in(locator : String, *, with content : String) : Nil
  el = __find_field(locator)
  el.fill(content)
end

private def __find_field(locator : String) : LuckyFlow::Element
  if (el = LuckyFlow.driver.find_css("##{locator}").first?)
    return el
  end
  if (el = LuckyFlow.driver.find_css(%([name="#{locator}"])).first?)
    return el
  end
  labels = LuckyFlow.driver.find_xpath("//label[normalize-space(text())=#{__xpath_lit(locator)}]")
  if (label = labels.first?)
    target_id = label.attribute("for")
    if target_id && !target_id.empty? && (el = LuckyFlow.driver.find_css("##{target_id}").first?)
      return el
    end
  end
  raise "fill_in: no field matching #{locator.inspect} (tried #id, [name=], <label for>)"
end

# Capybara's `click_on` — buttons / submits / anchors by visible text, then
# falls back to aria-label, title, id, name attributes (matches Capybara's
# fallback chain for clicks).
def click_on(locator : String) : Nil
  lit = __xpath_lit(locator)
  candidates = LuckyFlow.driver.find_xpath(
    "//button[normalize-space(.)=#{lit} or @aria-label=#{lit} or @title=#{lit}]" \
    " | //input[@type='submit' and (@value=#{lit} or @name=#{lit})]" \
    " | //a[normalize-space(.)=#{lit} or @aria-label=#{lit} or @title=#{lit}]" \
    " | //*[@id=#{lit} or @name=#{lit}]"
  )
  el = candidates.first?
  raise "click_on: no clickable element matching #{locator.inspect}" if el.nil?
  el.click
end

def click_button(locator : String) : Nil
  click_on(locator)
end

# ---------------- assertions ----------------

def assert_text(content : String) : Nil
  __retry_until("assert_text: page never contained #{content.inspect}") do
    page_text.includes?(content)
  end
end

def assert_selector(css : String, *, text : String? = nil) : Nil
  __retry_until("assert_selector: no element matching #{css.inspect}#{text.nil? ? "" : " containing #{text.inspect}"}") do
    elements = LuckyFlow.driver.find_css(css)
    next false if elements.empty?
    next true if text.nil?
    elements.any? { |el| el.text.includes?(text) }
  end
end

def assert_current_path(expected : String) : Nil
  __retry_until("assert_current_path: expected #{expected.inspect} got #{current_path.inspect}") do
    current_path == expected
  end
end

# ---------------- low-level ----------------

def page_text : String
  LuckyFlow.driver.find_css("body").first?.try(&.text) || ""
end

def execute_script(js : String) : String
  drv = LuckyFlow.driver
  case drv
  when LuckyFlow::Selenium::Driver then drv.execute_script(js)
  else                                  raise "execute_script: driver #{drv.class} has no JS bridge"
  end
end

# LuckyFlow's abstract Driver doesn't expose execute_script; only the Selenium
# session does, and it's behind a `private getter`. Reopen to surface it.
abstract class LuckyFlow::Selenium::Driver
  def execute_script(script : String) : String
    session.document_manager.execute_script(script)
  end

  # Send raw key events to whatever the document currently considers "active".
  # Mirrors Capybara's `page.send_keys :arrow_right`. Selenium W3C calls this
  # "actions" → key down/up; the simplest portable path is dispatch via JS so
  # we don't need the full actions API.
  def press_key(key : String) : Nil
    session.document_manager.execute_script(
      <<-JS
      const el = document.activeElement || document.body;
      const ev = new KeyboardEvent('keydown', { key: #{key.to_json}, bubbles: true });
      el.dispatchEvent(ev);
      JS
    )
  end
end

def find_by_id(id : String) : LuckyFlow::Element
  el = LuckyFlow.driver.find_css("##{id}").first?
  raise "find_by_id: no element with id #{id.inspect}" if el.nil?
  el
end

# Sign-in via the real form. The session cookie set on the driver persists
# across visits within a spec.
def sign_in(user : Accounts::User, password : String = "secret123456") : Nil
  visit "/session/new"
  fill_in "email_address", with: user.email.to_s
  fill_in "password", with: password
  click_on "Sign in"
  __retry_until("sign_in: still on /session/new after submitting credentials") do
    current_path != "/session/new"
  end
end

# Public retry helper — block returns truthy when the condition has settled.
def wait_until(failure_message : String = "wait_until: condition never became true", &) : Nil
  __retry_until(failure_message) { yield }
end

# ---------------- internals ----------------

def __retry_until(failure_message : String, &) : Nil
  deadline = Time.instant + LuckyFlow.settings.stop_retrying_after
  loop do
    return if yield
    break if Time.instant > deadline
    sleep(LuckyFlow.settings.retry_delay)
  end
  raise failure_message
end

# Escape a string into an XPath literal (no escape sequences in XPath).
private def __xpath_lit(value : String) : String
  return %("#{value}") unless value.includes?('"')
  return %('#{value}') unless value.includes?('\'')
  parts = value.split('"').map { |s| %("#{s}") }
  "concat(#{parts.join(", '\"', ")})"
end
