require "../../spec_helper"

# Port of writebook-rails/test/controllers/books/bookmarks_controller_test.rb.
#
# In Rails, the bookmark frame surfaces either a "Resume reading" or a
# "Start reading" link, picking between the two based on the
# `reading_progress_<book_id>` cookie. The Marten handler does the same
# but the visible link text in the template is `for-screen-reader`-only
# ("Resume reading <book>" vs "Start reading <book>") — we assert against
# those strings since the rest of the markup is asset/icon noise.
describe "Books::BookmarksHandler" do
  it "shows a Resume reading link when the cookie points at an active leaf" do
    Spec::Factories.create_account
    kevin = Spec::Factories.create_user(email: "kevin@example.com")
    handbook = Spec::Factories.create_book(title: "Handbook", editor: kevin)
    welcome = Spec::Factories.create_page_leaf(book: handbook, title: "Welcome")

    client = Marten::Spec.client
    Spec::Sessions.sign_in_as(client, kevin)
    client.cookies["reading_progress_#{handbook.pk}"] = welcome.pk.to_s

    response = client.get(Marten.routes.reverse("books:bookmark", book_id: handbook.pk!))

    response.status.should eq(200)
    response.content.should contain("Resume reading")
    response.content.should contain("Handbook")
  end

  it "shows a Start reading link when the cookie points at a trashed leaf" do
    Spec::Factories.create_account
    kevin = Spec::Factories.create_user(email: "kevin@example.com")
    handbook = Spec::Factories.create_book(title: "Handbook", editor: kevin)
    welcome = Spec::Factories.create_page_leaf(book: handbook, title: "Welcome")
    welcome.trashed!

    client = Marten::Spec.client
    Spec::Sessions.sign_in_as(client, kevin)
    client.cookies["reading_progress_#{handbook.pk}"] = welcome.pk.to_s

    response = client.get(Marten.routes.reverse("books:bookmark", book_id: handbook.pk!))

    response.status.should eq(200)
    response.content.should contain("Start reading")
  end

  it "shows a Start reading link when no reading_progress cookie is set" do
    Spec::Factories.create_account
    kevin = Spec::Factories.create_user(email: "kevin@example.com")
    handbook = Spec::Factories.create_book(title: "Handbook", editor: kevin)
    Spec::Factories.create_page_leaf(book: handbook, title: "Welcome")

    client = Marten::Spec.client
    Spec::Sessions.sign_in_as(client, kevin)

    response = client.get(Marten.routes.reverse("books:bookmark", book_id: handbook.pk!))

    response.status.should eq(200)
    response.content.should contain("Start reading")
  end

  it "shows a Start reading link when the cookie value is malformed" do
    Spec::Factories.create_account
    kevin = Spec::Factories.create_user(email: "kevin@example.com")
    handbook = Spec::Factories.create_book(title: "Handbook", editor: kevin)
    Spec::Factories.create_page_leaf(book: handbook, title: "Welcome")

    client = Marten::Spec.client
    Spec::Sessions.sign_in_as(client, kevin)
    client.cookies["reading_progress_#{handbook.pk}"] = "not-a-number"

    response = client.get(Marten.routes.reverse("books:bookmark", book_id: handbook.pk!))

    response.status.should eq(200)
    response.content.should contain("Start reading")
  end

  it "404s when the book does not exist" do
    Spec::Factories.create_account
    kevin = Spec::Factories.create_user(email: "kevin@example.com")

    client = Marten::Spec.client
    Spec::Sessions.sign_in_as(client, kevin)

    response = client.get(Marten.routes.reverse("books:bookmark", book_id: 999_999))
    response.status.should eq(404)
  end
end
