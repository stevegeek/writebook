module Books
  # Per-book full-text search. Public (no sign-in required).
  #
  # GET /books/<book_id:int>/search?q=<terms>
  class BooksSearchesHandler < Marten::Handler
    include ::Accounts::AuthenticationHelpers
    include BookScoped

    before_dispatch :require_book

    def get
      target_book = book!
      query = request.query_params["q"]?.try(&.strip)
      results = if query && !query.empty?
        Searchable.search(query, book_id: target_book.pk!.to_i64)
      else
        [] of NamedTuple(leaf: Leaf, title_match: String?, content_match: String?)
      end

      render("books/searches/create.html", context: {
        book:      target_book,
        query:     query || "",
        results:   results,
        signed_in: signed_in?,
      })
    end
  end
end
