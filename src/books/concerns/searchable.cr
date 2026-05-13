module Books
  # SQLite FTS5 integration for `Leaf`. Maintains a `leaf_search_index`
  # virtual table — the migration for which is hand-written raw SQL since
  # Marten doesn't have native FTS5 support.
  #
  # NOTE: The `after_*_commit` callbacks are intentionally NOT declared inside
  # `macro included` — Crystal macro scoping doesn't reliably propagate
  # class-level callback registrations from inside a concern. Instead, the
  # callbacks are declared directly on `Leaf` (in leaf.cr). Method bodies
  # live here so Leaf can call them.
  module Searchable
    INVALID_QUERY_CHARS = /[^\w"]/

    def self.sanitize_query(terms : String?) : String?
      return nil if terms.nil?
      cleaned = terms.gsub(INVALID_QUERY_CHARS, " ")
      cleaned = cleaned.gsub('"', " ") if cleaned.count('"').odd?
      stripped = cleaned.strip
      stripped.empty? ? nil : stripped
    end

    # Search across the FTS index, optionally scoped to a single book.
    # Returns tuples with the matched Leaf and highlight/snippet strings.
    def self.search(
      terms : String?,
      book_id : Int64? = nil,
    ) : Array(NamedTuple(leaf: Leaf, title_match: String?, content_match: String?))
      cleaned = sanitize_query(terms)
      return [] of NamedTuple(leaf: Leaf, title_match: String?, content_match: String?) if cleaned.nil?

      if book_id
        sql = <<-SQL
          SELECT books_leaf.id,
                 highlight(leaf_search_index, 0, '<mark>', '</mark>') AS title_match,
                 snippet(leaf_search_index, 1, '<mark>', '</mark>', '...', 20) AS content_match
          FROM books_leaf
          JOIN leaf_search_index ON books_leaf.id = leaf_search_index.rowid
          WHERE books_leaf.status = 'active'
            AND books_leaf.book_id = ?
            AND leaf_search_index MATCH ?
          ORDER BY bm25(leaf_search_index, 2.0)
          LIMIT 50
        SQL
      else
        sql = <<-SQL
          SELECT books_leaf.id,
                 highlight(leaf_search_index, 0, '<mark>', '</mark>') AS title_match,
                 snippet(leaf_search_index, 1, '<mark>', '</mark>', '...', 20) AS content_match
          FROM books_leaf
          JOIN leaf_search_index ON books_leaf.id = leaf_search_index.rowid
          WHERE books_leaf.status = 'active' AND leaf_search_index MATCH ?
          ORDER BY bm25(leaf_search_index, 2.0)
          LIMIT 50
        SQL
      end

      results = [] of NamedTuple(leaf: Leaf, title_match: String?, content_match: String?)
      Marten::DB::Connection.default.open do |db|
        if book_id
          db.query sql, book_id, cleaned do |rs|
            rs.each do
              leaf_id = rs.read(Int64)
              title_match = rs.read(String?)
              content_match = rs.read(String?)
              leaf = Leaf.get(pk: leaf_id)
              results << {
                leaf:          leaf.not_nil!,
                title_match:   title_match.try { |s| ::Books::HtmlScrubber.sanitize_search_result(s) },
                content_match: content_match.try { |s| ::Books::HtmlScrubber.sanitize_search_result(s) },
              } if leaf
            end
          end
        else
          db.query sql, cleaned do |rs|
            rs.each do
              leaf_id = rs.read(Int64)
              title_match = rs.read(String?)
              content_match = rs.read(String?)
              leaf = Leaf.get(pk: leaf_id)
              results << {
                leaf:          leaf.not_nil!,
                title_match:   title_match.try { |s| ::Books::HtmlScrubber.sanitize_search_result(s) },
                content_match: content_match.try { |s| ::Books::HtmlScrubber.sanitize_search_result(s) },
              } if leaf
            end
          end
        end
      end
      results
    end

    def reindex : Nil
      update_in_search_index if searchable?
    end

    private def searchable? : Bool
      !searchable_content.nil?
    end

    private def searchable_content : String?
      target = leafable
      case target
      when Leafables::Page
        target.searchable_content
      when Leafables::Section
        target.searchable_content
      when Leafables::Picture
        target.searchable_content
      else
        nil
      end
    end

    private def create_in_search_index : Nil
      return unless searchable?
      Marten::DB::Connection.default.open do |db|
        db.exec(
          "INSERT INTO leaf_search_index(rowid, title, content) VALUES (?, ?, ?)",
          pk, sanitize(title.to_s), sanitize(searchable_content.to_s),
        )
      end
    end

    private def update_in_search_index : Nil
      return unless searchable?
      # Contentless FTS5 (`content=''`) doesn't allow UPDATE — only INSERT/DELETE.
      # Delete-then-insert is the canonical reindex pattern.
      Marten::DB::Connection.default.open do |db|
        db.exec("DELETE FROM leaf_search_index WHERE rowid = ?", pk)
        db.exec(
          "INSERT INTO leaf_search_index(rowid, title, content) VALUES (?, ?, ?)",
          pk, sanitize(title.to_s), sanitize(searchable_content.to_s),
        )
      end
    end

    private def remove_from_search_index : Nil
      Marten::DB::Connection.default.open do |db|
        db.exec("DELETE FROM leaf_search_index WHERE rowid = ?", pk)
      end
    end

    # Strip every HTML tag from text destined for the FTS index. Mirrors
    # Rails Leaf::Searchable#sanitize_for_index (which uses
    # Rails::Html::FullSanitizer.new.sanitize).
    private def sanitize(text : String) : String
      ::Books::HtmlScrubber.strip_all(text)
    end
  end
end
