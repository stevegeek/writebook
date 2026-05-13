require "../../spec_helper"

# Port of writebook-rails/test/controllers/action_text/markdown/uploads_controller_test.rb.
#
# Rails' ActionText::Markdown::UploadsController exposes two endpoints:
#   - POST /markdown_uploads — attach a file to a Markdown row identified
#     by a signed gid + attribute name; returns JSON `{fileUrl: "/u/<slug>"}`.
#   - GET  /u/<slug>          — redirect to the underlying storage URL with a
#     long-lived public Cache-Control header.
#
# These power the house-md editor's inline file-upload button (see
# `src/assets/javascript/controllers/upload_preview_controller.js` +
# `src/books/templates/pages/_house_toolbar.html`).
#
# Implementation lives in `src/books/handlers/markdown_uploads_handler.cr` and
# resolves the host record via `Books::SignedGlobalId` (covered separately
# in `spec/books/signed_global_id_spec.cr`).
describe "Books::MarkdownUploadsCreateHandler" do
  # Build the multipart form fixture (record_gid, attribute_name, file) and
  # POST it. Verifies the 201/JSON response shape + the Attachment row that
  # backs the returned fileUrl.
  it "attach a file" do
    Spec::Factories.create_account
    kevin = Spec::Factories.create_user(email: "kevin@example.com")
    handbook = Spec::Factories.create_book(title: "Handbook", editor: kevin)
    leaf = Spec::Factories.create_page_leaf(book: handbook, title: "P", body: "x")
    page = leaf.page.not_nil!

    # `body=` already saved a Markdown row via has_markdown.
    md = Books::Markdown.filter(record_type: "Books::Leafables::Page", record_id: page.pk!).first.not_nil!
    gid = page.signed_global_id(purpose: "markdown_upload")

    client = Marten::Spec.client
    Spec::Sessions.sign_in_as(client, kevin)

    before_count = Books::Attachment.all.count

    response = post_multipart(
      client,
      Marten.routes.reverse("markdown_uploads_create"),
      fields: {"record_gid" => gid, "attribute_name" => "body"},
      file_field: "file",
      filename: "hello.png",
      content: "PNG\x00bytes",
      content_type: "image/png",
    )

    response.status.should eq(201)
    body = JSON.parse(response.content)
    file_url = body["fileUrl"].as_s
    file_url.should start_with("/u/")
    file_url.should end_with(".png")

    Books::Attachment.all.count.should eq(before_count + 1)
    new_attachment = Books::Attachment.filter(name: "uploads").order("-id").first.not_nil!
    new_attachment.record_type.should eq("Books::Markdown")
    new_attachment.record_id.to_s.should eq(md.pk!.to_s)
    new_attachment.slug.should_not be_nil
    file_url.should eq("/u/#{new_attachment.slug!}")
  end

  it "rejects an unsigned/garbled record_gid with 422" do
    Spec::Factories.create_account
    kevin = Spec::Factories.create_user(email: "kevin@example.com")
    Spec::Factories.create_book(title: "Handbook", editor: kevin)

    client = Marten::Spec.client
    Spec::Sessions.sign_in_as(client, kevin)

    response = post_multipart(
      client,
      Marten.routes.reverse("markdown_uploads_create"),
      fields: {"record_gid" => "garbage", "attribute_name" => "body"},
      file_field: "file",
      filename: "hello.png",
      content: "PNG",
      content_type: "image/png",
    )

    response.status.should eq(422)
  end

  it "requires authentication" do
    Spec::Factories.create_account
    kevin = Spec::Factories.create_user(email: "kevin@example.com")
    book = Spec::Factories.create_book(title: "Handbook", editor: kevin)
    gid = book.signed_global_id(purpose: "markdown_upload")

    client = Marten::Spec.client  # not signed in

    response = post_multipart(
      client,
      Marten.routes.reverse("markdown_uploads_create"),
      fields: {"record_gid" => gid, "attribute_name" => "body"},
      file_field: "file",
      filename: "hello.png",
      content: "PNG",
      content_type: "image/png",
    )

    # The before_dispatch :require_authentication callback redirects to
    # the sign-in page. (NOT a 401 — Rails' Authentication concern uses
    # the same redirect pattern.)
    response.status.should eq(302)
  end
end

describe "Books::MarkdownUploadsShowHandler" do
  it "view attached file" do
    Spec::Factories.create_account
    Spec::Factories.create_user(email: "kevin@example.com")
    Spec::Factories.create_book(title: "Handbook")
    page = Books::Leafables::Page.create!
    page.body = "x"
    md = Books::Markdown.filter(record_type: "Books::Leafables::Page", record_id: page.pk!).first.not_nil!

    # Reuse MartenStorages::Service.attach so the Attachment row's
    # `file` field gets a real backing file. Then set the slug
    # afterwards (the model owns the slug; Service.attach doesn't).
    part_headers = HTTP::Headers{
      "Content-Disposition" => %(form-data; name="file"; filename="hello.png"),
      "Content-Type"        => "image/png",
    }
    part = HTTP::FormData::Part.new(headers: part_headers, body: IO::Memory.new("PNG\x00bytes"))
    uploaded = Marten::HTTP::UploadedFile.new(part)

    attachment = MartenStorages::Service.attach(
      model: Books::Attachment,
      record: md,
      name: "uploads",
      uploaded_file: uploaded,
    )
    attachment.slug = "deadbeef.png"
    attachment.save!

    response = Marten::Spec.client.get("/u/deadbeef.png")
    response.status.should eq(302)
    response.headers["Location"].not_nil!.should_not be_empty
    response.headers["Cache-Control"].should eq("public, max-age=31536000")
  end

  it "404s on an unknown slug" do
    response = Marten::Spec.client.get("/u/unknown-slug.png")
    response.status.should eq(404)
  end
end

# Builds a multipart/form-data POST against the spec client. Marten's
# `request.data` parses multipart, so this is the route to drive the
# UploadedFile path end-to-end from a spec.
private def post_multipart(client, path : String, *, fields : Hash(String, String),
                           file_field : String, filename : String, content : String,
                           content_type : String)
  io = IO::Memory.new
  builder = HTTP::FormData::Builder.new(io, boundary: "----WriteBookSpecBoundary")

  fields.each { |key, value| builder.field(key, value) }
  builder.file(
    file_field,
    IO::Memory.new(content),
    HTTP::FormData::FileMetadata.new(filename: filename),
    HTTP::Headers{"Content-Type" => content_type},
  )
  builder.finish

  client.post(
    path,
    data: io.to_s,
    content_type: builder.content_type,
  )
end
