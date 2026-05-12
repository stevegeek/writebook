require "../../spec_helper"

describe "Books::Book" do
  describe "slug" do
    it "is generated from title" do
      book = Books::Book.create!(title: "Hello, World!")
      book.slug.should eq("hello-world")
    end
  end

  describe "#markable" do
    it "combines all active leafables" do
      book = Spec::Factories.create_book(title: "Handbook")
      Spec::Factories.create_page_leaf(book, title: "Welcome", body: "Welcome page content")
      Spec::Factories.create_page_leaf(book, title: "Summary", body: "Summary page content")

      book.markable.should contain("Welcome page content")
      book.markable.should contain("Summary page content")
    end

    it "joins leafables with double newlines" do
      book = Spec::Factories.create_book(title: "Handbook")
      Spec::Factories.create_page_leaf(book, title: "Welcome", body: "Welcome content")
      Spec::Factories.create_page_leaf(book, title: "Summary", body: "Summary content")

      book.markable.should contain("Welcome content\n\nSummary content")
    end

    it "only includes active leaves" do
      book = Spec::Factories.create_book(title: "Handbook")
      Spec::Factories.create_page_leaf(book, title: "Welcome", body: "Active content")
      summary = Spec::Factories.create_page_leaf(book, title: "Trashed Summary", body: "Trashed content")
      summary.trashed!

      book.markable.should contain("Active content")
      book.markable.should_not contain("Trashed content")
    end

    it "returns empty string for a book with no leaves" do
      book = Spec::Factories.create_book(title: "Empty")
      book.markable.should eq("")
    end
  end

  pending "press: building a leaf from a leafable + title" do
    # FIXME(porting gap): Rails' Book#press(leafable, title:) is not ported.
    # The Marten side constructs Leaf rows directly (see factories or
    # PagesHandler#create). If a `press`-style helper is added later, this
    # test should mirror the Rails assertion that the resulting leaf is a
    # page wrapper with the given title and body.
  end
end
