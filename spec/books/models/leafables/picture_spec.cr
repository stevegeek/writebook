require "../../../spec_helper"

describe "Books::Leafables::Picture" do
  describe "#markable" do
    it "returns the caption" do
      picture = Books::Leafables::Picture.new(caption: "A great picture")

      picture.markable.should eq("A great picture")
    end

    it "returns empty string when caption is nil" do
      # Note: Rails returns `nil` here; the Marten port's `markable` is
      # typed `: String` (so Book#markable can `join` it). Treating an
      # absent caption as "" is equivalent for export purposes.
      picture = Books::Leafables::Picture.new(caption: nil)

      picture.markable.should eq("")
    end
  end
end
