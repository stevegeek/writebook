module Books
  # Inline file uploads from the markdown editor. Mirrors Rails Writebook's
  # `ActionText::Markdown::UploadsController` (`app/controllers/action_text/markdown/uploads_controller.rb`).
  #
  # Two endpoints:
  #
  # - POST /markdown_uploads
  #     Form params:
  #       record_gid     — signed token (Books::SignedGlobalId) identifying
  #                        the record that owns the markdown attribute
  #       attribute_name — e.g. "body" — names the Markdown row on that record
  #       file           — the multipart-uploaded file
  #     Response: JSON `{fileUrl: "/u/<slug>"}` so the editor can splice the
  #     URL into the markdown source (`![alt](fileUrl)`).
  #
  # - GET /u/<slug>
  #     Look up the attachment by slug → 302 to the storage URL with a
  #     long-lived public Cache-Control header.

  # POST endpoint. Authenticated.
  class MarkdownUploadsCreateHandler < Marten::Handler
    include ::Accounts::AuthenticationHelpers

    before_dispatch :require_authentication

    SLUG_BYTES = 16

    def post
      record = SignedGlobalId.locate(
        request.data["record_gid"]?.try(&.to_s),
        purpose: "markdown_upload"
      )
      return respond("Invalid record", status: 422) if record.nil?

      attribute_name = request.data["attribute_name"]?.try(&.to_s).presence
      return respond("Missing attribute_name", status: 422) if attribute_name.nil?

      # safe_attribute returns nil unless `record` actually has a Markdown
      # row for that attribute name — gates against scribbling files onto
      # unrelated records via the signed-gid bypass.
      markdown = Markdown.safe_attribute(record, attribute_name)
      return respond("Unknown markdown attribute", status: 422) if markdown.nil?

      uploaded = request.data["file"]?.try(&.as?(Marten::HTTP::UploadedFile))
      return respond("Missing file", status: 422) if uploaded.nil?

      attachment = MartenStorages::Service.attach(
        model: Attachment,
        record: markdown,
        name: "uploads",
        uploaded_file: uploaded,
      )
      attachment.slug = build_slug(uploaded.filename)
      attachment.save!

      file_url = Marten.routes.reverse("markdown_upload_show", slug: attachment.slug!)
      respond(
        {"fileUrl" => file_url}.to_json,
        content_type: "application/json",
        status: 201,
      )
    end

    # `<random>.<ext>` — random 16-byte hex prefix + original file extension.
    # Mirrors Rails' `ActiveStorage::Blob#signed_id`-prefixed-with-extension
    # convention closely enough to be useful: markdown editors and image
    # viewers infer content-type from URL extensions.
    private def build_slug(original_filename : String?) : String
      ext = if original_filename && (idx = original_filename.rindex('.'))
              original_filename[idx..]
            else
              ""
            end
      "#{Random::Secure.hex(SLUG_BYTES)}#{ext}"
    end
  end

  # GET endpoint. Public — slug is unguessable (HMAC-strength via Random::Secure)
  # so unauthenticated access is acceptable. Mirrors Rails' `redirect_to
  # @attachment.url; expires_in 1.year, public: true`.
  class MarkdownUploadsShowHandler < Marten::Handler
    def get
      slug = params["slug"]?.try(&.to_s)
      return respond("Not found", status: 404) if slug.nil?

      attachment = Attachment.filter(slug: slug).first
      return respond("Not found", status: 404) if attachment.nil?

      url = attachment.file.url.to_s
      response = redirect(url)
      response.headers["Cache-Control"] = "public, max-age=31536000"
      response
    end
  end
end
