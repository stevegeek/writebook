Marten.routes.draw do
  # Root → books index. Plain alias since Books::BooksIndexHandler also lives
  # at /books inside the Books::ROUTES mount.
  path "/", Books::BooksIndexHandler, name: "root"

  # Accounts UX flows are top-level URLs (/first_run, /session/new, etc.) —
  # mount with empty prefix to keep flat URLs while retaining the
  # `accounts:*` route-name namespace.
  path "", Accounts::ROUTES, name: "accounts"

  # Books CRUD lives under /books/.
  path "/books", Books::ROUTES, name: "books"

  # Pages and sections show/edit are addressable by leaf id, flat URLs.
  path "/pages", Books::PAGE_ROUTES, name: "pages"
  path "/sections", Books::SECTION_ROUTES, name: "sections"
  path "/pictures", Books::PICTURE_ROUTES, name: "pictures"

  # Leaf edit-history. Scoped per-leaf: /leaves/<id>/edits[/<id>].
  path "/leaves", Books::EDIT_ROUTES, name: "edits"

  # Markdown editor uploads — mirrors Rails Writebook's `action_text` scope.
  # Top-level URLs keep the editor's client-side request path stable across
  # host record types.
  path "/markdown_uploads", Books::MarkdownUploadsCreateHandler, name: "markdown_uploads_create"
  path "/u/<slug:str>", Books::MarkdownUploadsShowHandler, name: "markdown_upload_show"

  # Assets are also served in test env so system specs can drive the real JS
  # layer (Turbo / Stimulus / house-md). Handler specs hit handlers in-process
  # and don't fetch assets, so the route is inert for them.
  if Marten.env.development? || Marten.env.test?
    path "#{Marten.settings.assets.url}<path:path>", Marten::Handlers::Defaults::Development::ServeAsset, name: "asset"
    path "#{Marten.settings.media_files.url}<path:path>", Marten::Handlers::Defaults::Development::ServeMediaFile, name: "media_file"
  end
end
