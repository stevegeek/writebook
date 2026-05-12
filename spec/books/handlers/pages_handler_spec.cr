require "../../spec_helper"

# Port of writebook-rails/test/controllers/pages_controller_test.rb.
#
# Rails → Marten mapping (9 Rails tests; * = pending porting gap):
#   Rails "show"                            -> "renders the page body"
#   Rails "show sanitizes dangerous content"-> *"renders dangerous HTML through the sanitizer"
#   Rails "show with HTML content"          -> *"preserves inline HTML inside markdown"
#   Rails "show with iframes"               -> *"preserves iframes in markdown"
#   Rails "show with tables"                -> *"renders markdown tables"
#   Rails "create"                          -> *"honors submitted title and body"
#                                              + "creates a new page leaf and responds with a turbo stream"
#                                                (book-scoping + count-+1 portion)
#   Rails "create with default params"      -> "creates a new page leaf and responds with a turbo stream"
#                                              (Marten default is "New page", Rails default is "Untitled")
#   Rails "create at a specific position"   -> *"honors a submitted position param"
#   Rails "update"                          -> "renders the edit form for a page"
#                                              + "updates a page and returns 204 for XHR/turbo autosaves"
#
# Marten URL shape differs from Rails:
#   - Show is `/pages/<id>` (flat-by-leaf-id), not nested under the book.
#   - Inline-create is `POST /books/<book_id>/pages` (route: books:pages_create).
#   - Edit is `/pages/<id>/edit` (route: pages:edit).
#
# Rails-style nested `book_pages_path(book, format: :turbo_stream)` doesn't
# exist; the Marten equivalent is `books:pages_create`, which responds with a
# turbo-stream when Accept: text/vnd.turbo-stream.html and 302 otherwise.
describe "Books::PagesShowHandler" do
  # Ports Rails "show".
  it "renders the page body" do
    Spec::Factories.create_account
    kevin = Spec::Factories.create_user(email: "kevin@example.com")
    handbook = Spec::Factories.create_book(title: "Handbook", editor: kevin)
    leaf = Spec::Factories.create_page_leaf(book: handbook, title: "Sample", body: "## Hello")

    client = Marten::Spec.client
    Spec::Sessions.sign_in_as(client, kevin)

    response = client.get(Marten.routes.reverse("pages:show", id: leaf.pk!))

    response.status.should eq(200)
    response.content.should contain("Hello")
  end

  # Ports Rails "show with tables in the markdown".
  # FIXME(porting gap): the Marten port uses `markd` (CommonMark) for
  # markdown rendering, which does NOT support GFM tables. Rails uses
  # Redcarpet with tables enabled. Enabling tables in markdown rendering
  # is a separate piece of work — re-enable this test once a GFM-table-aware
  # renderer (or markd extension) is wired up.
  pending "renders markdown tables" do
  end

  # Ports Rails "show sanitizes dangerous content".
  # FIXME(porting gap): the Marten markdown renderer's sanitize policy hasn't
  # been audited against the Rails version. Rails tests assert that
  # <div id="test"><script>alert("ouch")</script></div> survives as plain text
  # inside the wrapper div (script tag stripped, text preserved) and that
  # iframes/style attributes are kept verbatim. Confirm the renderer matches
  # before un-pending these.
  pending "renders dangerous HTML through the sanitizer" do
  end

  # Ports Rails "show with HTML content in the markdown".
  pending "preserves inline HTML inside markdown" do
  end

  # Ports Rails "show with iframes".
  pending "preserves iframes in markdown" do
  end

  it "404s when the leaf doesn't exist" do
    Spec::Factories.create_account
    kevin = Spec::Factories.create_user(email: "kevin@example.com")
    Spec::Factories.create_book(title: "Handbook", editor: kevin)

    client = Marten::Spec.client
    Spec::Sessions.sign_in_as(client, kevin)

    response = client.get(Marten.routes.reverse("pages:show", id: 999_999))
    response.status.should eq(404)
  end
end

describe "Books::PagesCreateHandler" do
  # Ports Rails "create" (count + book-scope assertions) and Rails
  # "create with default params" (Marten default title is "New page";
  # Rails default is "Untitled"). The behaviours are parallel but the
  # literal default differs intentionally.
  it "creates a new page leaf and responds with a turbo stream" do
    Spec::Factories.create_account
    kevin = Spec::Factories.create_user(email: "kevin@example.com")
    handbook = Spec::Factories.create_book(title: "Handbook", editor: kevin)

    client = Marten::Spec.client
    Spec::Sessions.sign_in_as(client, kevin)

    before_count = Books::Leaf.all.count
    response = client.post(
      Marten.routes.reverse("books:pages_create", book_id: handbook.pk!),
      headers: {"Accept" => "text/vnd.turbo-stream.html"},
    )

    response.status.should eq(200)
    Books::Leaf.all.count.should eq(before_count + 1)
    new_leaf = Books::Leaf.filter(book_id: handbook.pk).order("-id").first.not_nil!
    new_leaf.title.should eq("New page")
    new_leaf.leafable_type.should eq("Books::Leafables::Page")
  end

  it "redirects on a non-turbo POST" do
    Spec::Factories.create_account
    kevin = Spec::Factories.create_user(email: "kevin@example.com")
    handbook = Spec::Factories.create_book(title: "Handbook", editor: kevin)

    client = Marten::Spec.client
    Spec::Sessions.sign_in_as(client, kevin)

    before_count = Books::Leaf.all.count
    response = client.post(
      Marten.routes.reverse("books:pages_create", book_id: handbook.pk!),
      headers: {"Accept" => "text/html"},
    )

    response.status.should eq(302)
    response.headers["Location"].should eq(Marten.routes.reverse("books:show", id: handbook.pk!))
    Books::Leaf.all.count.should eq(before_count + 1)
  end

  # Ports Rails "create" (the title/body-from-params portion).
  # FIXME(porting gap): Marten's PagesCreateHandler is "inline-create" — it
  # makes an empty Page+Leaf with title "New page" and ignores any submitted
  # leaf[title]/page[body] fields. Rails' equivalent accepts those params and
  # also a `position` param to insert at a specific index. Both behaviours
  # need to be added to PagesCreateHandler before these tests can pass.
  pending "honors submitted title and body" do
  end

  # Ports Rails "create at a specific position".
  pending "honors a submitted position param" do
  end

  it "forbids non-editors" do
    Spec::Factories.create_account
    kevin = Spec::Factories.create_user(email: "kevin@example.com")
    reader = Spec::Factories.create_user(email: "reader@example.com")
    handbook = Spec::Factories.create_book(title: "Handbook", editor: kevin)
    Spec::Factories.create_access(user: reader, book: handbook, level: "reader")

    client = Marten::Spec.client
    Spec::Sessions.sign_in_as(client, reader)

    before_count = Books::Leaf.all.count
    response = client.post(
      Marten.routes.reverse("books:pages_create", book_id: handbook.pk!),
      headers: {"Accept" => "text/vnd.turbo-stream.html"},
    )

    response.status.should eq(403)
    Books::Leaf.all.count.should eq(before_count)
  end
end

describe "Books::PagesEditHandler" do
  # Ports the GET-edit portion of Rails "update".
  it "renders the edit form for a page" do
    Spec::Factories.create_account
    kevin = Spec::Factories.create_user(email: "kevin@example.com")
    handbook = Spec::Factories.create_book(title: "Handbook", editor: kevin)
    leaf = Spec::Factories.create_page_leaf(book: handbook, title: "Welcome", body: "Welcome content")

    client = Marten::Spec.client
    Spec::Sessions.sign_in_as(client, kevin)

    response = client.get(Marten.routes.reverse("pages:edit", id: leaf.pk!))
    response.status.should eq(200)
    response.content.should contain("Welcome")
  end

  # Ports the PUT-update portion of Rails "update" (asserts the new
  # title + body persist and the response is 204 for autosaves).
  it "updates a page and returns 204 for XHR/turbo autosaves" do
    Spec::Factories.create_account
    kevin = Spec::Factories.create_user(email: "kevin@example.com")
    handbook = Spec::Factories.create_book(title: "Handbook", editor: kevin)
    leaf = Spec::Factories.create_page_leaf(book: handbook, title: "Welcome", body: "Old body")

    client = Marten::Spec.client
    Spec::Sessions.sign_in_as(client, kevin)

    response = client.post(
      Marten.routes.reverse("pages:edit", id: leaf.pk!),
      data: {"title" => "Better welcome", "body" => "With even more interesting words."},
      headers: {"X-Requested-With" => "XMLHttpRequest"},
    )

    response.status.should eq(204)

    leaf.reload
    leaf.title.should eq("Better welcome")
    page = leaf.leafable.try(&.as?(Books::Leafables::Page)).not_nil!
    page.body.try(&.content).should eq("With even more interesting words.")
  end

  it "redirects to books:show on a non-XHR full-form submit" do
    Spec::Factories.create_account
    kevin = Spec::Factories.create_user(email: "kevin@example.com")
    handbook = Spec::Factories.create_book(title: "Handbook", editor: kevin)
    leaf = Spec::Factories.create_page_leaf(book: handbook, title: "Welcome", body: "Old body")

    client = Marten::Spec.client
    Spec::Sessions.sign_in_as(client, kevin)

    response = client.post(
      Marten.routes.reverse("pages:edit", id: leaf.pk!),
      data: {"title" => "Better welcome", "body" => "Better body"},
      headers: {"Accept" => "text/html"},
    )

    response.status.should eq(302)
    response.headers["Location"].should eq(Marten.routes.reverse("books:show", id: handbook.pk!))
  end
end
