require "../../spec_helper"

# Port placeholder for writebook-rails/test/controllers/action_text/markdown/uploads_controller_test.rb.
#
# Rails' ActionText::Markdown::UploadsController exposes two endpoints:
#   - POST /action_text/markdown/uploads — attach a file (e.g. image) to a
#     markdown body via signed GlobalID; returns JSON `{fileUrl: "/..."}`.
#   - GET  /action_text/markdown/uploads/:slug — redirect to the underlying
#     ActiveStorage blob URL.
#
# These power the house-md editor's inline file-upload button (see
# `src/assets/javascript/controllers/upload_preview_controller.js` +
# `src/books/templates/pages/_house_toolbar.html`).
#
# The Marten port hasn't shipped this handler/route yet — see
# `STATUS.md` ("storage upload pipeline … untested at runtime") and the
# `GlobalID::Locator.locate_signed` shard placeholder. The
# `Books::Attachment` model + `AttachmentHelpers.attach` machinery is
# wired for `name: "uploads"` on `Books::Markdown`, but no endpoint
# accepts the multipart POST or serves the slug-based redirect.
#
# When the upload handler lands:
#   - port "attach a file" → assert Books::Attachment count changes by 1
#     and JSON response `fileUrl` starts with "/"
#   - port "view attached file" → assert GET /…/uploads/:slug redirects to
#     the storage URL containing the original filename.
describe "ActionText::Markdown::UploadsHandler (Marten port)" do
  pending "attach a file" do
    # FIXME(porting gap): handler not yet ported. See file header for
    # the planned shape (POST to a new MarkdownUploadsHandler that
    # resolves a signed record GID + attribute_name, attaches the
    # multipart `file`, and returns `{fileUrl: …}`).
  end

  pending "view attached file" do
    # FIXME(porting gap): handler not yet ported. See file header for
    # the planned shape (GET by `slug` → 302 to the underlying
    # attachment's storage URL).
  end
end
