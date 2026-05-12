require "../../spec_helper"

# Port of writebook-rails/test/controllers/books/publications_controller_test.rb.
#
# Marten differences worth noting:
# - The Rails handler uses HTTP PATCH; the Marten handler is POST-only.
# - The Marten port flips `book.published` from the `published` form param
#   (mirrors a Marten check_box: presence == true, absence == false).
# - Slug editing is not yet ported (Books::Book has no slug field on the
#   publication form), so the "edit book slug" Rails test is captured here
#   as a `pending` porting gap.
describe "Books::BookPublicationHandler" do
  describe "GET /books/<id>/publication" do
    it "renders the publication frame for editors" do
      Spec::Factories.create_account
      david = Spec::Factories.create_user(email: "david@example.com")
      manual = Spec::Factories.create_book(title: "Manual", editor: david)

      client = Marten::Spec.client
      Spec::Sessions.sign_in_as(client, david)

      response = client.get(Marten.routes.reverse("books:publication", id: manual.pk!))
      response.status.should eq(200)
      # The publication partial renders a turbo-frame with the lock/publish switch.
      response.content.should contain("publication_books_book_#{manual.pk}")
    end

    it "redirects to sign-in for anonymous visitors" do
      Spec::Factories.create_account
      Spec::Factories.create_user(email: "david@example.com")
      manual = Spec::Factories.create_book(title: "Manual")

      response = Marten::Spec.client.get(Marten.routes.reverse("books:publication", id: manual.pk!))

      response.status.should eq(302)
    end

    it "403s for signed-in users without editor access" do
      Spec::Factories.create_account
      david = Spec::Factories.create_user(email: "david@example.com")
      manual = Spec::Factories.create_book(title: "Manual") # no access for david

      client = Marten::Spec.client
      Spec::Sessions.sign_in_as(client, david)

      response = client.get(Marten.routes.reverse("books:publication", id: manual.pk!))
      response.status.should eq(403)
    end

    it "404s when the book does not exist" do
      Spec::Factories.create_account
      david = Spec::Factories.create_user(email: "david@example.com")

      client = Marten::Spec.client
      Spec::Sessions.sign_in_as(client, david)

      response = client.get(Marten.routes.reverse("books:publication", id: 999_999))
      response.status.should eq(404)
    end
  end

  describe "POST /books/<id>/publication" do
    # The handler dispatches on `request.turbo?` (i.e. `Accept: text/vnd.turbo-stream.html`)
    # to choose between a turbo-stream replace and a plain redirect. Marten's `accepts?`
    # treats `*/*` as a match, so omitting the Accept header makes the handler take the
    # turbo branch. We explicitly send `Accept: text/html` for the redirect-path tests.
    html_headers = {"Accept" => "text/html"}

    it "publishes a book and redirects to the show page" do
      Spec::Factories.create_account
      david = Spec::Factories.create_user(email: "david@example.com")
      manual = Spec::Factories.create_book(title: "Manual", editor: david, published: false)

      client = Marten::Spec.client
      Spec::Sessions.sign_in_as(client, david)

      response = client.post(
        Marten.routes.reverse("books:publication", id: manual.pk!),
        data: {"published" => "1"},
        headers: html_headers,
      )

      response.status.should eq(302)
      response.headers["Location"].should eq(Marten.routes.reverse("books:show", id: manual.pk!))

      manual.reload
      manual.published.should be_true
    end

    it "unpublishes a book when published=0 is submitted" do
      Spec::Factories.create_account
      david = Spec::Factories.create_user(email: "david@example.com")
      manual = Spec::Factories.create_book(title: "Manual", editor: david, published: true)

      client = Marten::Spec.client
      Spec::Sessions.sign_in_as(client, david)

      response = client.post(
        Marten.routes.reverse("books:publication", id: manual.pk!),
        data: {"published" => "0"},
        headers: html_headers,
      )

      response.status.should eq(302)
      manual.reload
      manual.published.should be_false
    end

    it "treats a missing `published` param as unpublish" do
      # Marten check_box convention: absent param == false. Mirrors the
      # browser submission when the hidden `published=0` companion is dropped.
      Spec::Factories.create_account
      david = Spec::Factories.create_user(email: "david@example.com")
      manual = Spec::Factories.create_book(title: "Manual", editor: david, published: true)

      client = Marten::Spec.client
      Spec::Sessions.sign_in_as(client, david)

      response = client.post(
        Marten.routes.reverse("books:publication", id: manual.pk!),
        data: {"other" => "noop"},
        headers: html_headers,
      )
      response.status.should eq(302)

      manual.reload
      manual.published.should be_false
    end

    it "renders a turbo-stream response for turbo requests" do
      Spec::Factories.create_account
      david = Spec::Factories.create_user(email: "david@example.com")
      manual = Spec::Factories.create_book(title: "Manual", editor: david, published: false)

      client = Marten::Spec.client
      Spec::Sessions.sign_in_as(client, david)

      response = client.post(
        Marten.routes.reverse("books:publication", id: manual.pk!),
        data: {"published" => "1"},
        headers: {"Accept" => "text/vnd.turbo-stream.html"},
      )

      response.status.should eq(200)
      response.content.should contain("turbo-stream")
      response.content.should contain("publication_books_book_#{manual.pk}")
      manual.reload
      manual.published.should be_true
    end

    it "403s when a non-editor tries to publish" do
      Spec::Factories.create_account
      david = Spec::Factories.create_user(email: "david@example.com")
      manual = Spec::Factories.create_book(title: "Manual", published: false) # no access for david

      client = Marten::Spec.client
      Spec::Sessions.sign_in_as(client, david)

      response = client.post(
        Marten.routes.reverse("books:publication", id: manual.pk!),
        data: {"published" => "1"},
        headers: html_headers,
      )

      response.status.should eq(403)
      manual.reload
      manual.published.should be_false
    end
  end

  pending "edit book slug" do
    # FIXME(porting gap): The Marten port doesn't yet ship a slug field on
    # Books::Book (see books/publications/_publication.html — slug edit
    # button is TODO'd out). When that lands, this test should PATCH
    # `book: { slug: "new-slug" }` and assert the redirect uses the new slug.
  end
end
