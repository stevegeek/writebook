module Books
  # BookmarksHandler — turbo-frame fragment that shows a "Resume reading"
  # link (or a plain cover link) based on the reading_progress_<book_id> cookie.
  # The frame is lazy-loaded from _book.html so the library page stays fast.
  class BookmarksHandler < Marten::Handler
    include ::Accounts::AuthenticationHelpers

    def get
      book = Book.get(pk: params["book_id"]?)
      return respond("Not found", status: 404) if book.nil?

      cookie_key = "reading_progress_#{book.pk}"
      leaf_id = request.cookies[cookie_key]?

      leaf = nil
      if leaf_id && !leaf_id.empty?
        parsed_id = leaf_id.to_i64?
        leaf = book.leaves.filter(status: "active").filter(id: parsed_id).first if parsed_id
      end

      render("books/bookmarks/show.html", context: {book: book, leaf: leaf})
    end
  end
end
