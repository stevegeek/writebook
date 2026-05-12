require "../../../spec_helper"

describe "Books::Leafables::Section" do
  describe "#markable" do
    it "returns body content" do
      section = Books::Leafables::Section.new(body: "Section Content")

      section.markable.should eq("Section Content")
    end

    it "returns empty string when body is nil" do
      # Note: Rails returns `nil` (so assert_nil) when body is nil; the Marten
      # port returns "" instead because `markable` is typed `: String` and
      # callers (Book#markable, exports) join on it. This is a deliberate
      # contract divergence — `""` is treated as "skip" by Book#markable.
      section = Books::Leafables::Section.new(body: nil)

      section.markable.should eq("")
    end
  end

  describe "#searchable_content" do
    it "returns the body" do
      section = Books::Leafables::Section.new(body: "Find me")

      section.searchable_content.should eq("Find me")
    end

    it "returns nil when body is nil" do
      section = Books::Leafables::Section.new(body: nil)

      section.searchable_content.should be_nil
    end
  end

  describe "#body_html" do
    it "wraps single paragraphs in <p>" do
      section = Books::Leafables::Section.new(body: "Hello world")

      section.body_html.should eq("<p>Hello world</p>")
    end

    it "splits double-newline paragraphs into separate <p> tags" do
      section = Books::Leafables::Section.new(body: "First\n\nSecond")

      section.body_html.should contain("<p>First</p>")
      section.body_html.should contain("<p>Second</p>")
    end

    it "escapes HTML special characters" do
      section = Books::Leafables::Section.new(body: "Tom & <Jerry>")

      section.body_html.should contain("Tom &amp; &lt;Jerry&gt;")
    end

    it "returns empty string when body is empty" do
      section = Books::Leafables::Section.new(body: "")

      section.body_html.should eq("")
    end
  end
end
