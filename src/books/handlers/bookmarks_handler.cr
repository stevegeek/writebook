module Books
  # BookmarksHandler — turbo-frame fragment that shows a "Resume reading"
  # link (or a plain cover link) based on the reading_progress_<book_id> cookie.
  # The frame is lazy-loaded from _book.html so the library page stays fast.
  class BookmarksHandler < Marten::Handler
    include ::Accounts::AuthenticationHelpers
    include BookScoped

    before_dispatch :require_book

    def get
      leaf = last_read_leaf_id.try { |id| book!.leaves.active.get(id: id) }
      render("books/bookmarks/show.html", context: {book: book!, leaf: leaf})
    end

    private def last_read_leaf_id : Int64?
      request.cookies["reading_progress_#{book!.pk}"]?.try(&.to_i64?)
    end
  end
end
