module Books
  # Manages per-user editor/reader access for a book.
  # GET  /books/<book_id>/accesses — renders user list with current access state
  # POST /books/<book_id>/accesses — updates access and redirects to book show
  class AccessesHandler < Marten::Handler
    include ::Accounts::AuthenticationHelpers
    include RequestParams

    @book : Book? = nil

    before_dispatch :require_authentication
    before_dispatch :load_book
    before_dispatch :ensure_editable

    def get
      render("books/accesses/edit.html", context: context_data)
    end

    def post
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
      if book.everyone_access != everyone
        book.update!(everyone_access: everyone)
      end

      book.update_access(editor_ids: editor_ids, reader_ids: reader_ids)

      redirect(Marten.routes.reverse("books:show", id: book.pk!))
    end

    private def book : Book
      @book.not_nil!
    end

    private def load_book : Marten::HTTP::Response?
      @book = Book.get(pk: params["book_id"]?)
      if @book.nil?
        return head :not_found
      end
      nil
    end

    private def ensure_editable : Marten::HTTP::Response?
      unless book.editable?(current_user)
        return head :forbidden
      end
      nil
    end

    private def context_data
      users = ::Accounts::User.active.ordered.to_a

      # Pre-compute sets so the template doesn't need to call methods with user args.
      accesses = ::Accounts::Access.filter(book_id: book.pk!).to_a
      editor_ids = accesses.select(&.editor?).compact_map { |a| pk_to_i64(a.user_id) }
      reader_ids = accesses.compact_map { |a| pk_to_i64(a.user_id) }

      {
        book:       book,
        users:      users,
        editor_ids: editor_ids,
        reader_ids: reader_ids,
        signed_in:  true,
      }
    end
  end
end
