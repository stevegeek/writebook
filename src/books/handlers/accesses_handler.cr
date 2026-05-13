module Books
  # Manages per-user editor/reader access for a book.
  # GET  /books/<book_id>/accesses — renders user list with current access state
  # POST /books/<book_id>/accesses — updates access and redirects to book show
  class AccessesHandler < Marten::Handler
    include ::Accounts::AuthenticationHelpers
    include BookScoped
    include RequestParams

    before_dispatch :require_authentication
    before_dispatch :require_book
    before_dispatch :ensure_editable

    def get
      render("books/accesses/edit.html", context: context_data)
    end

    def post
      target_book = book!
      editor_ids = collect_ids("editor_ids")
      reader_ids = collect_ids("reader_ids")

      # Always include the current user as editor+reader
      if (uid = pk_to_i64(current_user.try(&.id)))
        editor_ids << uid unless editor_ids.includes?(uid)
        reader_ids << uid unless reader_ids.includes?(uid)
      end

      # Persist the everyone_access flag from the form *before* update_access
      # so update_access sees the correct value when expanding readers.
      everyone_raw = request.data["everyone_access"]?.to_s
      everyone = everyone_raw == "1" || everyone_raw == "true"
      if target_book.everyone_access != everyone
        target_book.update!(everyone_access: everyone)
      end

      target_book.update_access(editor_ids: editor_ids, reader_ids: reader_ids)

      redirect(Marten.routes.reverse("books:show", id: target_book.pk!))
    end

    private def context_data
      target_book = book!
      users = ::Accounts::User.active.ordered.to_a

      # Pre-compute sets so the template doesn't need to call methods with user args.
      accesses = ::Accounts::Access.filter(book_id: target_book.pk!).to_a
      editor_ids = accesses.select(&.editor?).compact_map { |a| pk_to_i64(a.user_id) }
      reader_ids = accesses.compact_map { |a| pk_to_i64(a.user_id) }

      {
        book:       target_book,
        users:      users,
        editor_ids: editor_ids,
        reader_ids: reader_ids,
        signed_in:  true,
      }
    end
  end
end
