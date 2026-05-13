require "../spec_helper"

# Ports `writebook-rails/test/helpers/searches_helper_test.rb`.
#
# Rails defined a `SearchesHelper#sanitize_search_result` method that took
# raw FTS5 `highlight()`/`snippet()` output and returned a sanitized HTML
# string preserving only `<mark>` tags. The Marten port has no such
# helper:
#
#   - The FTS5 `highlight()` / `snippet()` calls live in
#     `Books::Searchable.search` (`src/books/concerns/searchable.cr`)
#     and run against SQL-side data that was already stripped of HTML
#     before being indexed (`Searchable#sanitize` in that file).
#   - The search results template
#     (`src/books/templates/books/searches/create.html`) renders the raw
#     `title_match` / `content_match` strings with the `|safe` filter,
#     trusting the index-time sanitization.
#
# The Marten port now ships `Books::HtmlScrubber.sanitize_search_result`
# (in `src/books/html_scrubber.cr`) as the direct analog of the Rails
# helper. `Searchable.search` runs the FTS5 highlight/snippet output
# through it before returning, so even pre-sanitized index rows are
# defended at render time as well.
describe "Search sanitization (port of Rails SearchesHelper)" do
  describe "Books::Searchable.sanitize_query (input sanitizer)" do
    it "returns nil for nil input" do
      Books::Searchable.sanitize_query(nil).should be_nil
    end

    it "returns nil for blank input" do
      Books::Searchable.sanitize_query("   ").should be_nil
    end

    it "strips characters outside the [\\w\"] safelist" do
      # `&`, `<`, `>` get replaced with spaces and collapsed by `strip`.
      Books::Searchable.sanitize_query("Tom & Jerry").should eq("Tom   Jerry")
    end

    it "removes an unbalanced quote so FTS5 doesn't choke" do
      Books::Searchable.sanitize_query(%(needle"haystack)).should eq("needle haystack")
    end

    it "keeps balanced quoted phrases intact" do
      Books::Searchable.sanitize_query(%("exact phrase")).should eq(%("exact phrase"))
    end
  end

  describe "Books::HtmlScrubber.sanitize_search_result" do
    it "preserves <mark> tags" do
      input = %(plain <mark>highlighted</mark> plain)
      Books::HtmlScrubber.sanitize_search_result(input).should contain("<mark>highlighted</mark>")
    end

    it "strips non-mark tags but keeps text content" do
      input = %(<b>bold</b> <mark>match</mark> <script>alert(1)</script>)
      out = Books::HtmlScrubber.sanitize_search_result(input)
      out.should_not contain("<b>")
      # libxml2-based sanitizer drops the <script> tag AND its content —
      # stricter than Rails Loofah, which keeps the text. The visible
      # "bold" stays because it lived outside the disallowed tag.
      out.should_not contain("<script>")
      out.should contain("bold")
      out.should contain("<mark>match</mark>")
    end

    it "encodes entities outside tags" do
      Books::HtmlScrubber.sanitize_search_result("Tom & Jerry").should eq("Tom &amp; Jerry")
    end

    it "strips attributes from mark tags" do
      input = %(<mark class="evil" onclick="x">match</mark>)
      Books::HtmlScrubber.sanitize_search_result(input).should eq("<mark>match</mark>")
    end
  end
end
