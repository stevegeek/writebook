require "../../spec_helper"

# Port of writebook-rails/test/controllers/books/leaves/moves_controller_test.rb.
#
# Rails → Marten mapping (2 Rails tests; all ported):
#   Rails "moving a single item"    -> "moves a single leaf to the requested position"
#   Rails "moving multiple items"   -> "moves multiple leaves together with the primary as the head"
#
# POST /books/<book_id>/leaves/moves
#   - `position`: target 0-based index
#   - `id[]`:     one or more leaf ids; the first is the primary leaf, the
#                 rest "follow" it.
# Returns 204 on success, 403/404/422 on the obvious failure modes.
describe "Books::LeavesMovesHandler" do
  # Ports Rails "moving a single item".
  it "moves a single leaf to the requested position" do
    Spec::Factories.create_account
    kevin = Spec::Factories.create_user(email: "kevin@example.com")
    handbook = Spec::Factories.create_book(title: "Handbook", editor: kevin)
    welcome_section = Spec::Factories.create_section_leaf(book: handbook, title: "Welcome Section")
    welcome_page = Spec::Factories.create_page_leaf(book: handbook, title: "Welcome Page")
    summary_page = Spec::Factories.create_page_leaf(book: handbook, title: "Summary Page")
    reading_picture = Spec::Factories.create_picture_leaf(book: handbook, title: "Reading Picture")

    Books::Leaf.filter(book_id: handbook.pk).order(:position_score, :id).to_a.map(&.pk).should eq(
      [welcome_section.pk, welcome_page.pk, summary_page.pk, reading_picture.pk]
    )

    client = Marten::Spec.client
    Spec::Sessions.sign_in_as(client, kevin)

    response = client.post(
      Marten.routes.reverse("books:leaves_moves", book_id: handbook.pk!),
      data: {"id[]" => [welcome_page.pk!.to_s], "position" => "0"},
    )

    response.status.should eq(204)

    Books::Leaf.filter(book_id: handbook.pk).order(:position_score, :id).to_a.map(&.pk).should eq(
      [welcome_page.pk, welcome_section.pk, summary_page.pk, reading_picture.pk]
    )
  end

  # Ports Rails "moving multiple items".
  it "moves multiple leaves together with the primary as the head" do
    Spec::Factories.create_account
    kevin = Spec::Factories.create_user(email: "kevin@example.com")
    handbook = Spec::Factories.create_book(title: "Handbook", editor: kevin)
    welcome_section = Spec::Factories.create_section_leaf(book: handbook, title: "Welcome Section")
    welcome_page = Spec::Factories.create_page_leaf(book: handbook, title: "Welcome Page")
    summary_page = Spec::Factories.create_page_leaf(book: handbook, title: "Summary Page")
    reading_picture = Spec::Factories.create_picture_leaf(book: handbook, title: "Reading Picture")

    client = Marten::Spec.client
    Spec::Sessions.sign_in_as(client, kevin)

    response = client.post(
      Marten.routes.reverse("books:leaves_moves", book_id: handbook.pk!),
      data: {"id[]" => [summary_page.pk!.to_s, reading_picture.pk!.to_s], "position" => "1"},
    )

    response.status.should eq(204)

    Books::Leaf.filter(book_id: handbook.pk).order(:position_score, :id).to_a.map(&.pk).should eq(
      [welcome_section.pk, summary_page.pk, reading_picture.pk, welcome_page.pk]
    )
  end

  it "forbids non-editors" do
    Spec::Factories.create_account
    kevin = Spec::Factories.create_user(email: "kevin@example.com")
    reader = Spec::Factories.create_user(email: "reader@example.com")
    handbook = Spec::Factories.create_book(title: "Handbook", editor: kevin)
    Spec::Factories.create_access(user: reader, book: handbook, level: "reader")
    welcome_page = Spec::Factories.create_page_leaf(book: handbook, title: "Welcome Page")

    client = Marten::Spec.client
    Spec::Sessions.sign_in_as(client, reader)

    response = client.post(
      Marten.routes.reverse("books:leaves_moves", book_id: handbook.pk!),
      data: {"id[]" => [welcome_page.pk!.to_s], "position" => "0"},
    )

    response.status.should eq(403)
  end

  it "404s when the book does not exist" do
    Spec::Factories.create_account
    kevin = Spec::Factories.create_user(email: "kevin@example.com")

    client = Marten::Spec.client
    Spec::Sessions.sign_in_as(client, kevin)

    response = client.post(
      Marten.routes.reverse("books:leaves_moves", book_id: 999_999),
      data: {"id[]" => ["1"], "position" => "0"},
    )

    response.status.should eq(404)
  end

  it "rejects GETs with method-not-allowed" do
    Spec::Factories.create_account
    kevin = Spec::Factories.create_user(email: "kevin@example.com")
    handbook = Spec::Factories.create_book(title: "Handbook", editor: kevin)

    client = Marten::Spec.client
    Spec::Sessions.sign_in_as(client, kevin)

    response = client.get(Marten.routes.reverse("books:leaves_moves", book_id: handbook.pk!))
    response.status.should eq(405)
  end
end
