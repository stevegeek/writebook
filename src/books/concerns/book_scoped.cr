module Books
  # Handler concern: fetches the requested Book by `params["book_id"]`, scoped
  # via `Book.accessable_or_published` so anonymous users only see published
  # books and signed-in users only see books they have access to. 404s if the
  # lookup misses. Mirrors the Rails Books::BookScoped concern.
  #
  # Requires `Accounts::AuthenticationHelpers` for `current_user`. Wire in:
  #
  #   class FooHandler < Marten::Handler
  #     include ::Accounts::AuthenticationHelpers
  #     include Books::BookScoped
  #     before_dispatch :require_book
  #   end
  module BookScoped
    @book : Book?

    protected def book : Book?
      @book ||= Book.accessable_or_published(current_user).get(pk: params["book_id"]?)
    end

    protected def book! : Book
      book.not_nil!
    end

    protected def require_book : Marten::HTTP::Response?
      return nil if book
      respond("Not found", status: 404)
    end

    protected def ensure_editable : Marten::HTTP::Response?
      return nil if book.try(&.editable?(current_user))
      respond("Forbidden", status: 403)
    end
  end
end
