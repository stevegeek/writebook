require "./spec_helper"

describe LeafableHelpers do
  describe "leafable_url / leafable_edit_url / leafable_class" do
    it "dispatches on a Page leaf's concrete leafable" do
      book = Spec::Factories.create_book(title: "B")
      leaf = Spec::Factories.create_page_leaf(book: book, title: "p", body: "x")
      page = leaf.page.not_nil!

      LeafableHelpers.leafable_url(leaf).should eq("/pages/#{page.pk}")
      LeafableHelpers.leafable_edit_url(leaf).should eq("/pages/#{page.pk}/edit")
      LeafableHelpers.leafable_class(leaf).should eq("page")
    end

    it "dispatches on a Section leaf" do
      book = Spec::Factories.create_book(title: "B")
      leaf = Spec::Factories.create_section_leaf(book: book, title: "s")
      section = leaf.section.not_nil!

      LeafableHelpers.leafable_url(leaf).should eq("/sections/#{section.pk}")
      LeafableHelpers.leafable_edit_url(leaf).should eq("/sections/#{section.pk}/edit")
      LeafableHelpers.leafable_class(leaf).should eq("section")
    end

    it "dispatches on a Picture leaf" do
      book = Spec::Factories.create_book(title: "B")
      leaf = Spec::Factories.create_picture_leaf(book: book, title: "pic")
      picture = leaf.picture.not_nil!

      LeafableHelpers.leafable_url(leaf).should eq("/pictures/#{picture.pk}")
      LeafableHelpers.leafable_edit_url(leaf).should eq("/pictures/#{picture.pk}/edit")
      LeafableHelpers.leafable_class(leaf).should eq("picture")
    end

    it "accepts a concrete leafable directly" do
      book = Spec::Factories.create_book(title: "B")
      leaf = Spec::Factories.create_page_leaf(book: book, title: "p", body: "x")
      page = leaf.page.not_nil!

      LeafableHelpers.leafable_url(page).should eq("/pages/#{page.pk}")
      LeafableHelpers.leafable_edit_url(page).should eq("/pages/#{page.pk}/edit")
    end
  end

  describe "{% leafable_url leaf %} template tag" do
    it "renders the show URL" do
      book = Spec::Factories.create_book(title: "B")
      leaf = Spec::Factories.create_page_leaf(book: book, title: "p", body: "x")
      template = Marten::Template::Template.new("{% leafable_url leaf %}")
      template.render(Marten::Template::Context{"leaf" => leaf}).should eq("/pages/#{leaf.page.not_nil!.pk}")
    end

    it "{% leafable_edit_url %} renders the edit URL" do
      book = Spec::Factories.create_book(title: "B")
      leaf = Spec::Factories.create_section_leaf(book: book, title: "s")
      template = Marten::Template::Template.new("{% leafable_edit_url leaf %}")
      template.render(Marten::Template::Context{"leaf" => leaf}).should eq("/sections/#{leaf.section.not_nil!.pk}/edit")
    end

    it "{% leafable_class %} renders the type name" do
      book = Spec::Factories.create_book(title: "B")
      leaf = Spec::Factories.create_picture_leaf(book: book, title: "pic")
      template = Marten::Template::Template.new("{% leafable_class leaf %}")
      template.render(Marten::Template::Context{"leaf" => leaf}).should eq("picture")
    end

    it "raises when the argument isn't a Leaf" do
      template = Marten::Template::Template.new("{% leafable_url thing %}")
      context = Marten::Template::Context{"thing" => "not a leaf"}
      expect_raises(Marten::Template::Errors::UnsupportedValue, /Books::Leaf/) do
        template.render(context)
      end
    end
  end
end
