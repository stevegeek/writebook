module Books
  # Tiny handler concern: 403s the request unless the signed-in user is
  # an editor of the current book. Mirrors the `before_action :ensure_editable`
  # callback that Rails' BooksController inherits from its own concerns.
  #
  # Three handler classes used to inline an identical `private def
  # ensure_editable` — BooksEditHandler, BooksDeleteHandler, and
  # BookPublicationHandler. They differ only in how they look up the book
  # (some via Marten's generic-handler `record`, one via a private `@book`
  # ivar). This concern requires the host to expose a `current_book : Book?`
  # method; the host decides whether that's `record` or its own loader.
  #
  # `Books::BookScoped` is the right concern when the book id lives in
  # `params["book_id"]` (nested routes); use this one when it's on `record`
  # or loaded by hand.
  module BookEditableGuard
    protected def ensure_editable : Marten::HTTP::Response?
      return nil if current_book.try(&.editable?(current_user))
      respond("Forbidden", status: 403)
    end
  end
end
