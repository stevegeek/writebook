require "../../spec_helper"

# Port of writebook-rails/test/controllers/pictures_controller_test.rb.
#
# Rails → Marten mapping (2 Rails tests; * = pending porting gap):
#   Rails "update picture"  -> "renders the edit form for a picture" (the GET-edit half)
#                              + *"updates the image binary via multipart upload" (the PUT-with-image half)
#   Rails "update caption"  -> "renders the edit form for a picture" (the GET-edit half)
#                              + "updates the caption without re-uploading an image" (the PUT-with-caption half)
#
# Marten URL shape:
#   - Inline-create: POST /books/<book_id>/pictures (books:pictures_create)
#   - Edit:          POST /pictures/<id>/edit       (pictures:edit)
#
# The Rails tests primarily exercise image upload through ActiveStorage with
# `fixture_file_upload`. The Marten port uses MartenStorages::Service.attach,
# which invokes vips to compute a "large" variant at upload time. Real-image
# uploads in unit specs would require a valid binary image file under the
# spec's working directory plus libvips on the runner. Those upload paths
# are flagged pending here; the non-file edit paths (caption-only) are
# exercised directly.
describe "Books::PicturesCreateHandler" do
  it "creates a new picture leaf via turbo stream" do
    Spec::Factories.create_account
    kevin = Spec::Factories.create_user(email: "kevin@example.com")
    handbook = Spec::Factories.create_book(title: "Handbook", editor: kevin)

    client = Marten::Spec.client
    Spec::Sessions.sign_in_as(client, kevin)

    before_count = Books::Leaf.all.count
    response = client.post(
      Marten.routes.reverse("books:pictures_create", book_id: handbook.pk!),
      headers: {"Accept" => "text/vnd.turbo-stream.html"},
    )

    response.status.should eq(200)
    Books::Leaf.all.count.should eq(before_count + 1)
    new_leaf = Books::Leaf.filter(book_id: handbook.pk).order("-id").first.not_nil!
    new_leaf.title.should eq("New picture")
    new_leaf.leafable_type.should eq("Books::Leafables::Picture")
  end

  it "redirects on a non-turbo POST" do
    Spec::Factories.create_account
    kevin = Spec::Factories.create_user(email: "kevin@example.com")
    handbook = Spec::Factories.create_book(title: "Handbook", editor: kevin)

    client = Marten::Spec.client
    Spec::Sessions.sign_in_as(client, kevin)

    response = client.post(
      Marten.routes.reverse("books:pictures_create", book_id: handbook.pk!),
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
      Marten.routes.reverse("books:pictures_create", book_id: handbook.pk!),
      headers: {"Accept" => "text/vnd.turbo-stream.html"},
    )

    response.status.should eq(403)
    Books::Leaf.all.count.should eq(before_count)
  end
end

describe "Books::PicturesEditHandler" do
  # Ports the GET-edit portion of both Rails "update picture" and
  # Rails "update caption".
  it "renders the edit form for a picture" do
    Spec::Factories.create_account
    kevin = Spec::Factories.create_user(email: "kevin@example.com")
    handbook = Spec::Factories.create_book(title: "Handbook", editor: kevin)
    leaf = Spec::Factories.create_picture_leaf(book: handbook, title: "Reading", caption: "Reading time")

    client = Marten::Spec.client
    Spec::Sessions.sign_in_as(client, kevin)

    response = client.get(Marten.routes.reverse("pictures:edit", id: leaf.pk!))
    response.status.should eq(200)
    response.content.should contain("Reading")
  end

  # Ports Rails "update caption" — PUT with just caption, no image upload.
  it "updates the caption without re-uploading an image" do
    Spec::Factories.create_account
    kevin = Spec::Factories.create_user(email: "kevin@example.com")
    handbook = Spec::Factories.create_book(title: "Handbook", editor: kevin)
    leaf = Spec::Factories.create_picture_leaf(book: handbook, title: "Reading", caption: "Old caption")

    client = Marten::Spec.client
    Spec::Sessions.sign_in_as(client, kevin)

    response = client.post(
      Marten.routes.reverse("pictures:edit", id: leaf.pk!),
      data: {"caption" => "New caption", "title" => "Reading"},
      headers: {"X-Requested-With" => "XMLHttpRequest"},
    )

    response.status.should eq(204)

    leaf.reload
    picture = leaf.leafable.try(&.as?(Books::Leafables::Picture)).not_nil!
    picture.caption.should eq("New caption")
  end

  # Ports the PUT-with-image-upload portion of Rails "update picture".
  # FIXME(porting gap): Uploading an image through the Marten test client
  # would require a real binary image (e.g. a small webp/png) under the
  # spec tree AND libvips on the runner — MartenStorages::Service.attach
  # invokes vips to compute the "large" variant. Mirror the Rails
  # `fixture_file_upload("white-rabbit.webp", "image/webp")` flow once a
  # spec image fixture is in place and the vips-dependent attach is
  # sandboxed for the test environment.
  pending "updates the image binary via multipart upload" do
  end
end
