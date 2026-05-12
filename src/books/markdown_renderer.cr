# Markdown → HTML renderer. Mirrors Writebook's MarkdownRenderer:
#   - server-side syntax highlighting via tartrazine on fenced code blocks,
#   - heading anchors for in-page links,
#   - lightbox-wrapped images with the `data-action="lightbox#open:prevent"` hook.
#
# Built on `markd` (CommonMark). Has a small post-processing pass that
# rewrites `<pre><code class="language-foo">…</code></pre>` blocks through
# tartrazine and rewrites `<img>` into the lightbox-wrapped form.
module Books::MarkdownRenderer
  extend self

  def render(source : String) : String
    options = Markd::Options.new(smart: true, safe: false)
    html = Markd.to_html(source, options)
    html = highlight_code_blocks(html)
    html = wrap_images(html)
    html = anchor_headings(html)
    html
  end

  # Rewrite `<pre><code class="language-foo">…</code></pre>` blocks via
  # tartrazine. Falls back to the unmodified block if the language isn't
  # recognised or highlighting raises.
  private def highlight_code_blocks(html : String) : String
    html.gsub(/<pre><code(?: class="language-([^"]+)")?>(.*?)<\/code><\/pre>/m) do |_match, m|
      # Group 1 (language) is optional — `m[1]?` guards against the
      # IndexError that direct `$1` access raises when unmatched.
      lang_str = m[1]?
      lang = (lang_str && !lang_str.empty?) ? lang_str : nil
      raw = decode_entities(m[2])
      highlight_or_passthrough(raw, lang)
    end
  end

  private def highlight_or_passthrough(code : String, lang : String?) : String
    return %(<pre><code>#{escape_html(code)}</code></pre>) if lang.nil?

    formatter = Tartrazine::Html.new(theme: Tartrazine.theme("github"), standalone: false, line_numbers: false)
    lexer = Tartrazine.lexer(name: lang)
    formatter.format(code, lexer)
  rescue
    %(<pre><code class="language-#{lang}">#{escape_html(code)}</code></pre>)
  end

  # Wrap top-level images in the lightbox-trigger anchor that Writebook's
  # template uses (`data-controller="lightbox" data-action="lightbox#open"`).
  private def wrap_images(html : String) : String
    html.gsub(/<img src="([^"]+)" alt="([^"]*)"(?: title="([^"]*)")?\s*\/?>/) do |_match, m|
      url = m[1]
      alt = m[2]
      title = m[3]?  # group 3 is optional
      title_attr = (title && !title.empty?) ? %( title="#{escape_html(title)}") : ""
      %(<a#{title_attr} data-action="lightbox#open:prevent" data-lightbox-target="image" ) +
        %(data-lightbox-url-value="#{url}?disposition=attachment" href="#{url}">) +
        %(<img src="#{url}" alt="#{escape_html(alt)}"></a>)
    end
  end

  # Add an `id` attribute and a permalink anchor to every heading. IDs
  # are deduplicated within a single render call.
  private def anchor_headings(html : String) : String
    counts = Hash(String, Int32).new(0)
    html.gsub(/<(h[1-6])>(.*?)<\/\1>/m) do |_match, m|
      level = m[1]
      text = m[2]
      base = slug_for(strip_tags(text))
      counts[base] += 1
      id = counts[base] > 1 ? "#{base}-#{counts[base]}" : base
      %(<#{level} id="#{id}">#{text} <a href="##{id}" class="heading__link" aria-hidden="true">#</a></#{level}>)
    end
  end

  private def slug_for(text : String) : String
    s = text.downcase.gsub(/[^a-z0-9]+/, "-").strip('-')
    s.empty? ? "section" : s
  end

  private def strip_tags(html : String) : String
    html.gsub(/<[^>]+>/, "")
  end

  private def escape_html(s : String) : String
    s.gsub('&', "&amp;").gsub('<', "&lt;").gsub('>', "&gt;").gsub('"', "&quot;")
  end

  private def decode_entities(s : String) : String
    s.gsub("&lt;", "<").gsub("&gt;", ">").gsub("&quot;", "\"").gsub("&#39;", "'").gsub("&amp;", "&")
  end
end
