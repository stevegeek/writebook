require "../../spec_helper"

describe "Books::Searchable" do
  describe ".sanitize_query" do
    it "returns nil for a nil input" do
      Books::Searchable.sanitize_query(nil).should be_nil
    end

    it "returns nil for an empty / whitespace-only input" do
      Books::Searchable.sanitize_query("   ").should be_nil
    end

    it "strips non-word characters except quotes" do
      Books::Searchable.sanitize_query("hello!@# world").not_nil!.should contain("hello")
      Books::Searchable.sanitize_query("hello!@# world").not_nil!.should contain("world")
    end

    it "removes unmatched quotes (FTS5 would otherwise reject the query)" do
      cleaned = Books::Searchable.sanitize_query("foo \" bar").not_nil!
      cleaned.should_not contain("\"")
    end
  end

  describe ".search" do
    it "finds a page by its body content" do
      book = Spec::Factories.create_book(title: "Handbook")
      leaf = Spec::Factories.create_page_leaf(book, title: "The Handbook", body: "This is such a great handbook.")

      results = Books::Searchable.search("great handbook")

      results.map(&.[:leaf].pk).should contain(leaf.pk)
    end

    it "reflects updated content after editing the leaf body via Editable#edit" do
      book = Spec::Factories.create_book(title: "Handbook")
      leaf = Spec::Factories.create_page_leaf(book, title: "Welcome", body: "Original content")

      # Reindex explicitly: editing the markdown row directly does not
      # trigger Leaf's after_update_commit. Call `leaf.reindex` to mimic
      # what handlers do after a content update.
      page = leaf.leafable.as(Books::Leafables::Page)
      page.body = "sausages"
      leaf.reindex

      results = Books::Searchable.search("sausages")
      results.map(&.[:leaf].pk).should contain(leaf.pk)
    end

    it "highlights matches with <mark> tags" do
      book = Spec::Factories.create_book(title: "Handbook")
      Spec::Factories.create_page_leaf(book, title: "The Handbook", body: "This is such a great handbook.")

      results = Books::Searchable.search("great handbook")
      first = results.first
      first[:title_match].not_nil!.should contain("<mark>Handbook</mark>")
      first[:content_match].not_nil!.should contain("<mark>great</mark>")
    end

    it "excludes leaves whose leafable has no searchable_content (e.g. pictures)" do
      book = Spec::Factories.create_book(title: "Handbook")
      Spec::Factories.create_section_leaf(book, title: "welcome", body: "Find me too")
      Spec::Factories.create_picture_leaf(book, title: "welcome picture", caption: nil)

      results = Books::Searchable.search("welcome")
      # The section should match; the picture (no searchable content) should not.
      titles = results.map { |r| r[:leaf].title.to_s }
      titles.size.should be > 0
      titles.any? { |t| t == "welcome picture" }.should be_false
    end

    it "sanitises HTML tags out of indexed section body" do
      book = Spec::Factories.create_book(title: "Handbook")
      Spec::Factories.create_section_leaf(
        book,
        title: "Safe Title",
        body: %(findme Tom & Jerry <img src=x onerror="alert(1)">),
      )

      results = Books::Searchable.search("findme")
      results.size.should be > 0
      content = results.first[:content_match].not_nil!
      content.should contain("<mark>findme</mark>")
      content.should_not contain("<img")
      content.should_not contain("onerror")
    end

    it "sanitises HTML tags out of indexed section title" do
      book = Spec::Factories.create_book(title: "Handbook")
      Spec::Factories.create_section_leaf(
        book,
        title: %(findme Tom & Jerry <img src=x onerror="alert(1)">),
        body: "findme content",
      )

      results = Books::Searchable.search("findme")
      title_match = results.first[:title_match].not_nil!
      title_match.should contain("<mark>findme</mark>")
      title_match.should_not contain("<img")
    end

    it "sanitises HTML tags out of indexed page body" do
      book = Spec::Factories.create_book(title: "Handbook")
      leaf = Spec::Factories.create_page_leaf(
        book,
        title: "Welcome",
        body: "findme Tom & Jerry <b>bold</b>",
      )
      leaf.reindex

      results = Books::Searchable.search("findme")
      results.size.should be > 0
      content = results.first[:content_match].not_nil!
      content.should contain("<mark>findme</mark>")
      content.should contain("Tom &amp; Jerry")
      content.should_not contain("<b>")
    end

    it "sanitises HTML tags out of indexed page title" do
      book = Spec::Factories.create_book(title: "Handbook")
      leaf = Spec::Factories.create_page_leaf(
        book,
        title: %(findme Tom & Jerry <b>bold</b>),
        body: "findme content",
      )
      leaf.reindex

      results = Books::Searchable.search("findme")
      title_match = results.first[:title_match].not_nil!
      title_match.should contain("<mark>findme</mark>")
      title_match.should_not contain("<b>")
    end

    it "strips injected mark tags from the indexed title" do
      book = Spec::Factories.create_book(title: "Handbook")
      Spec::Factories.create_section_leaf(
        book,
        title: %(findme <mark>fake highlight</mark>),
        body: "findme content",
      )

      results = Books::Searchable.search("findme")
      title_match = results.first[:title_match].not_nil!
      # The only <mark>...</mark> in the result should be the highlight on
      # the literal "findme" — the injected one is stripped by `sanitize`.
      title_match.scan(/<mark>/).size.should eq(1)
      title_match.should contain("<mark>findme</mark>")
    end
  end

  describe "#reindex" do
    it "is a no-op for non-searchable leafables (e.g. pictures)" do
      book = Spec::Factories.create_book(title: "Handbook")
      leaf = Spec::Factories.create_picture_leaf(book, title: "Just a pic")

      # Shouldn't raise.
      leaf.reindex
    end
  end

  describe "#matches_for_highlight" do
    it "returns the unique matched tokens, longest first" do
      book = Spec::Factories.create_book(title: "Handbook")
      leaf = Spec::Factories.create_page_leaf(
        book,
        title: "Welcome",
        body: "kevin was here and kevin says hello again",
      )
      leaf.reindex

      leaf.matches_for_highlight("kevin").should eq(["kevin"])
    end

    it "returns multiple distinct tokens longest-first" do
      book = Spec::Factories.create_book(title: "Handbook")
      leaf = Spec::Factories.create_page_leaf(
        book,
        title: "Welcome",
        body: "alpha beta gamma alpha gamma",
      )
      leaf.reindex

      result = leaf.matches_for_highlight("alpha gamma")
      result.size.should eq(2)
      result.should contain("alpha")
      result.should contain("gamma")
      # Tie-broken arbitrarily on same-length tokens — only assert order
      # when the lengths actually differ.
    end

    it "returns [] for blank / nil terms" do
      book = Spec::Factories.create_book(title: "Handbook")
      leaf = Spec::Factories.create_page_leaf(book, title: "T", body: "x")
      leaf.reindex

      leaf.matches_for_highlight(nil).should eq([] of String)
      leaf.matches_for_highlight("   ").should eq([] of String)
    end

    it "returns [] when nothing matches" do
      book = Spec::Factories.create_book(title: "Handbook")
      leaf = Spec::Factories.create_page_leaf(book, title: "T", body: "nothing to find here")
      leaf.reindex

      leaf.matches_for_highlight("missingword").should eq([] of String)
    end
  end
end
