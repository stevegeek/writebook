module Books
  ROUTES = Marten::Routing::Map.draw do
    path "", BooksIndexHandler, name: "index"
    path "/new", BooksNewHandler, name: "new"
    path "/<id:int>", BooksShowHandler, name: "show"
    path "/<id:int>/edit", BooksEditHandler, name: "edit"
    path "/<id:int>/delete", BooksDeleteHandler, name: "delete"
    path "/<book_id:int>/accesses", AccessesHandler, name: "accesses"

    path "/<book_id:int>/pages/new", PagesNewHandler, name: "pages_new"
    path "/<book_id:int>/sections/new", SectionsNewHandler, name: "sections_new"
    path "/<book_id:int>/pictures/new", PicturesNewHandler, name: "pictures_new"
    # Inline-create endpoints (POSTed from the TOC toolbar; respond turbo-stream).
    path "/<book_id:int>/pages", PagesCreateHandler, name: "pages_create"
    path "/<book_id:int>/sections", SectionsCreateHandler, name: "sections_create"
    path "/<book_id:int>/pictures", PicturesCreateHandler, name: "pictures_create"
    path "/<book_id:int>/search", BooksSearchesHandler, name: "search"

    path "/<book_id:int>/leaves/moves", LeavesMovesHandler, name: "leaves_moves"
    path "/<book_id:int>/leaves/<id:int>/delete", LeavesDestroyHandler, name: "leaf_delete"
    path "/<book_id:int>/bookmark", BookmarksHandler, name: "bookmark"
    path "/<id:int>/publication", BookPublicationHandler, name: "publication"
    path "/<id:int>/markdown", BooksMarkdownHandler, name: "markdown"
  end

  # Pages and sections show/edit are addressable by leaf id, not nested
  # under a book. Mounted at the project's root in config/routes.cr.
  PAGE_ROUTES = Marten::Routing::Map.draw do
    path "/<id:int>", PagesShowHandler, name: "show"
    path "/<id:int>/edit", PagesEditHandler, name: "edit"
    path "/<id:int>/markdown", PagesMarkdownHandler, name: "markdown"
  end

  SECTION_ROUTES = Marten::Routing::Map.draw do
    path "/<id:int>", SectionsShowHandler, name: "show"
    path "/<id:int>/edit", SectionsEditHandler, name: "edit"
    path "/<id:int>/markdown", SectionsMarkdownHandler, name: "markdown"
  end

  # Picture show/edit are addressable by leaf id. Mount at project root
  # in config/routes.cr alongside PAGE_ROUTES and SECTION_ROUTES.
  PICTURE_ROUTES = Marten::Routing::Map.draw do
    path "/<id:int>", PicturesShowHandler, name: "show"
    path "/<id:int>/edit", PicturesEditHandler, name: "edit"
    path "/<id:int>/markdown", PicturesMarkdownHandler, name: "markdown"
  end

  # Edit-history (revision) routes. Scoped by leaf id rather than nested
  # under a leafable type, which matches the Marten URL shape where
  # leaves are addressable directly by id. Rails nests under `pages`
  # because in Rails only Pages record edits; here we cover all leafable
  # types uniformly. The show handler accepts the literal string
  # "latest" as an id (mirrors Rails Pages::EditsController#show).
  EDIT_ROUTES = Marten::Routing::Map.draw do
    path "/<leaf_id:int>/edits", EditsIndexHandler, name: "index"
    # Two separate routes for `id`: integer (most calls) and a "latest"
    # alias (matches Rails Pages::EditsController#show). Marten parameter
    # types' `dumps` is strict — `int` only accepts integers, `slug` only
    # accepts strings — so a single combined `<id:str>` doesn't work for
    # reverse lookups with `id: edit.id` (an Int64).
    path "/<leaf_id:int>/edits/<id:int>", EditsShowHandler, name: "show"
    path "/<leaf_id:int>/edits/latest", EditsShowHandler, name: "show_latest"
  end
end
