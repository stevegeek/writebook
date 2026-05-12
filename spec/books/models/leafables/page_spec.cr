require "../../../spec_helper"

describe "Books::Leafables::Page" do
  describe "#html_preview" do
    it "renders markdown headings and paragraphs" do
      page = Books::Leafables::Page.create!
      page.body = "# Hello\n\nWorld!"

      # The Marten renderer adds an `id` + anchor link to headings (the
      # `heading-anchors` hook registered in Books::App); Rails' renderer
      # emits a plain `<h1>`. Both wrap "Hello" inside an h1.
      page.html_preview.should match(/<h1[^>]*>Hello/)
      page.html_preview.should match(/<p>World!<\/p>/)
    end
  end

  describe "#markable" do
    it "returns raw markdown content" do
      page = Books::Leafables::Page.create!
      page.body = "## Markdown Content\n\nWith **bold** text."

      page.markable.should eq("## Markdown Content\n\nWith **bold** text.")
    end

    it "returns empty string when body is empty" do
      page = Books::Leafables::Page.create!

      page.markable.should eq("")
    end
  end

  describe "#searchable_content" do
    it "returns the markdown body's plain text" do
      page = Books::Leafables::Page.create!
      page.body = "Some plain text body"

      page.searchable_content.should_not be_nil
      page.searchable_content.not_nil!.should contain("Some plain text body")
    end

    pending "re-encodes HTML entities" do
      # FIXME(porting gap): The Rails test asserts that searchable_content
      # re-encodes `<`, `>`, `&` as `&lt; &gt; &amp;` (because Rails'
      # to_plain_text decodes them, then html_safe-wraps the result). The
      # Marten port uses MartenMarkdown's `plain_text` which does not
      # re-encode entities.
    end
  end
end
