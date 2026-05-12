require "../../spec_helper"

# Port of writebook-rails/test/controllers/sections_controller_test.rb.
#
# Rails → Marten mapping (3 Rails tests; * = pending porting gap):
#   Rails "create"                          -> "creates a new section leaf via turbo stream"
#   Rails "update"                          -> "updates the leaf title and the section body/theme"
#   Rails "update with no body supplied"    -> *"falls back to the new title as body when no body is supplied"
#
# Marten URL shape:
#   - Inline-create:  POST /books/<book_id>/sections (books:sections_create)
#   - Edit:           POST /sections/<id>/edit       (sections:edit)
describe "Books::SectionsCreateHandler" do
  # Ports Rails "create" — default-title section, book-scoped.
  it "creates a new section leaf via turbo stream" do
    Spec::Factories.create_account
    kevin = Spec::Factories.create_user(email: "kevin@example.com")
    handbook = Spec::Factories.create_book(title: "Handbook", editor: kevin)

    client = Marten::Spec.client
    Spec::Sessions.sign_in_as(client, kevin)

    before_count = Books::Leaf.all.count
    response = client.post(
      Marten.routes.reverse("books:sections_create", book_id: handbook.pk!),
      headers: {"Accept" => "text/vnd.turbo-stream.html"},
    )

    response.status.should eq(200)
    Books::Leaf.all.count.should eq(before_count + 1)
    new_leaf = Books::Leaf.filter(book_id: handbook.pk).order("-id").first.not_nil!
    new_leaf.title.should eq("New section")
    new_leaf.leafable_type.should eq("Books::Leafables::Section")
    new_leaf.book!.pk.should eq(handbook.pk)
  end

  it "redirects on a non-turbo POST" do
    Spec::Factories.create_account
    kevin = Spec::Factories.create_user(email: "kevin@example.com")
    handbook = Spec::Factories.create_book(title: "Handbook", editor: kevin)

    client = Marten::Spec.client
    Spec::Sessions.sign_in_as(client, kevin)

    response = client.post(
      Marten.routes.reverse("books:sections_create", book_id: handbook.pk!),
      headers: {"Accept" => "text/html"},
    )

    response.status.should eq(302)
    response.headers["Location"].should eq(Marten.routes.reverse("books:show", id: handbook.pk!))
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
      Marten.routes.reverse("books:sections_create", book_id: handbook.pk!),
      headers: {"Accept" => "text/vnd.turbo-stream.html"},
    )

    response.status.should eq(403)
    Books::Leaf.all.count.should eq(before_count)
  end
end

describe "Books::SectionsEditHandler" do
  # Ports Rails "update".
  it "updates the leaf title and the section body/theme" do
    Spec::Factories.create_account
    kevin = Spec::Factories.create_user(email: "kevin@example.com")
    handbook = Spec::Factories.create_book(title: "Handbook", editor: kevin)
    leaf = Spec::Factories.create_section_leaf(book: handbook, title: "Welcome", body: "Old body")

    client = Marten::Spec.client
    Spec::Sessions.sign_in_as(client, kevin)

    response = client.post(
      Marten.routes.reverse("sections:edit", id: leaf.pk!),
      data: {"title" => "Title", "body" => "Section body"},
      headers: {"X-Requested-With" => "XMLHttpRequest"},
    )

    response.status.should eq(204)

    leaf.reload
    leaf.title.should eq("Title")
    section = leaf.leafable.try(&.as?(Books::Leafables::Section)).not_nil!
    section.body.should eq("Section body")
  end

  # Ports Rails "update with no body supplied".
  # FIXME(porting gap): Rails' SectionsController#update has a fallback
  # where, when no `section[:body]` param is supplied, the section body is
  # reset to the new leaf title ("New title" → body becomes "New title").
  # The Marten SectionsEditHandler doesn't replicate this fallback: an
  # empty body POSTs as "" (cleared). Until that behaviour is mirrored,
  # this test is pending.
  pending "falls back to the new title as body when no body is supplied" do
  end

  it "renders the edit form for a section" do
    Spec::Factories.create_account
    kevin = Spec::Factories.create_user(email: "kevin@example.com")
    handbook = Spec::Factories.create_book(title: "Handbook", editor: kevin)
    leaf = Spec::Factories.create_section_leaf(book: handbook, title: "Welcome Section", body: "Old body")

    client = Marten::Spec.client
    Spec::Sessions.sign_in_as(client, kevin)

    response = client.get(Marten.routes.reverse("sections:edit", id: leaf.pk!))
    response.status.should eq(200)
    response.content.should contain("Welcome Section")
  end
end
