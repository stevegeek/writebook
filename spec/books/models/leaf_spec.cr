require "../../spec_helper"

describe "Books::Leaf" do
  describe "#slug" do
    it "is generated from title" do
      leaf = Books::Leaf.new(title: "Hello, World!")

      leaf.slug.should eq("hello-world")
    end

    it "is never completely blank" do
      leaf = Books::Leaf.new(title: "")

      leaf.slug.should eq("-")
    end
  end
end
