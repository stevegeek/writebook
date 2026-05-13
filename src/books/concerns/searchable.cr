module Books
  # Full-text search for `Leaf`. Backed by SQLite FTS5 or by a generated
  # `tsvector` column on PostgreSQL. The schema for either lives in the
  # hand-written `leaf_search_index` migration. The `after_*_commit`
  # callbacks are declared directly on `Leaf` (in leaf.cr); method bodies
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

    # Convert a sanitized user query into a tsquery string suitable for
    # `to_tsquery`. Splits on whitespace, drops empty tokens, and ANDs the
    # rest together with prefix matching (`token:*`).
    def self.to_tsquery(cleaned : String) : String
      tokens = cleaned.split(/\s+/).reject(&.empty?).map { |t| "#{t}:*" }
      tokens.join(" & ")
    end

    def self.postgres? : Bool
      Marten::DB::Connection.default.scheme == "postgres"
    end

    # Search across the FTS index, optionally scoped to a single book.
    # Returns tuples with the matched Leaf and highlight/snippet strings.
    def self.search(
      terms : String?,
      book_id : Int64? = nil,
    ) : Array(NamedTuple(leaf: Leaf, title_match: String?, content_match: String?))
      cleaned = sanitize_query(terms)
      return [] of NamedTuple(leaf: Leaf, title_match: String?, content_match: String?) if cleaned.nil?

      if postgres?
        search_postgres(cleaned, book_id)
      else
        search_sqlite(cleaned, book_id)
      end
    end

    private def self.search_sqlite(
      cleaned : String,
      book_id : Int64?,
    ) : Array(NamedTuple(leaf: Leaf, title_match: String?, content_match: String?))
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

    private def self.search_postgres(
      cleaned : String,
      book_id : Int64?,
    ) : Array(NamedTuple(leaf: Leaf, title_match: String?, content_match: String?))
      tsq = to_tsquery(cleaned)
      empty_result = [] of NamedTuple(leaf: Leaf, title_match: String?, content_match: String?)
      return empty_result if tsq.empty?

      if book_id
        sql = <<-SQL
          SELECT books_leaf.id,
                 ts_headline('english', coalesce(idx.title, ''),   to_tsquery('english', $2),
                             'StartSel=<mark>, StopSel=</mark>, HighlightAll=TRUE') AS title_match,
                 ts_headline('english', coalesce(idx.content, ''), to_tsquery('english', $2),
                             'StartSel=<mark>, StopSel=</mark>, MaxFragments=1, MaxWords=20, MinWords=5') AS content_match
          FROM books_leaf
          JOIN leaf_search_index idx ON books_leaf.id = idx.rowid
          WHERE books_leaf.status = 'active'
            AND books_leaf.book_id = $1
            AND idx.tsv @@ to_tsquery('english', $2)
          ORDER BY ts_rank(idx.tsv, to_tsquery('english', $2)) DESC
          LIMIT 50
        SQL
        args = [book_id.as(::DB::Any), tsq.as(::DB::Any)]
      else
        sql = <<-SQL
          SELECT books_leaf.id,
                 ts_headline('english', coalesce(idx.title, ''),   to_tsquery('english', $1),
                             'StartSel=<mark>, StopSel=</mark>, HighlightAll=TRUE') AS title_match,
                 ts_headline('english', coalesce(idx.content, ''), to_tsquery('english', $1),
                             'StartSel=<mark>, StopSel=</mark>, MaxFragments=1, MaxWords=20, MinWords=5') AS content_match
          FROM books_leaf
          JOIN leaf_search_index idx ON books_leaf.id = idx.rowid
          WHERE books_leaf.status = 'active'
            AND idx.tsv @@ to_tsquery('english', $1)
          ORDER BY ts_rank(idx.tsv, to_tsquery('english', $1)) DESC
          LIMIT 50
        SQL
        args = [tsq.as(::DB::Any)]
      end

      results = empty_result
      Marten::DB::Connection.default.open do |db|
        db.query(sql, args: args) do |rs|
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
      results
    end

    def reindex : Nil
      update_in_search_index if searchable?
    end

    # Mirrors Rails `Leaf#matches_for_highlight(terms)` — returns the unique
    # matching tokens (longest first) for use by the search results template
    # to highlight matched terms outside of the index's own highlight.
    # Returns [] when the query is empty / invalid or the leaf isn't indexed.
    def matches_for_highlight(terms : String?) : Array(String)
      cleaned = Searchable.sanitize_query(terms)
      return [] of String if cleaned.nil?

      content = nil
      Marten::DB::Connection.default.open do |db|
        if Searchable.postgres?
          tsq = Searchable.to_tsquery(cleaned)
          return [] of String if tsq.empty?
          db.query(
            "SELECT ts_headline('english', coalesce(content, ''), to_tsquery('english', $2), " \
            "'StartSel=<mark>, StopSel=</mark>, HighlightAll=TRUE') AS h " \
            "FROM leaf_search_index WHERE rowid = $1 AND tsv @@ to_tsquery('english', $2)",
            args: [pk.as(::DB::Any), tsq.as(::DB::Any)]
          ) do |rs|
            rs.each { content = rs.read(String?) }
          end
        else
          db.query(
            "SELECT highlight(leaf_search_index, 1, '<mark>', '</mark>') AS h " \
            "FROM leaf_search_index WHERE rowid = ? AND leaf_search_index MATCH ?",
            pk, cleaned
          ) do |rs|
            rs.each { content = rs.read(String?) }
          end
        end
      end

      return [] of String if content.nil?
      content.not_nil!.scan(/<mark>(.*?)<\/mark>/).map(&.[1]).uniq.sort_by(&.size).reverse
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
        if Searchable.postgres?
          db.exec(
            "INSERT INTO leaf_search_index(rowid, title, content) VALUES ($1, $2, $3)",
            pk, sanitize(title.to_s), sanitize(searchable_content.to_s),
          )
        else
          db.exec(
            "INSERT INTO leaf_search_index(rowid, title, content) VALUES (?, ?, ?)",
            pk, sanitize(title.to_s), sanitize(searchable_content.to_s),
          )
        end
      end
    end

    private def update_in_search_index : Nil
      return unless searchable?
      # SQLite FTS5: even the content-bearing form is fine with DELETE+INSERT.
      # Postgres: same pattern, simple and avoids tsvector update gotchas.
      Marten::DB::Connection.default.open do |db|
        if Searchable.postgres?
          db.exec("DELETE FROM leaf_search_index WHERE rowid = $1", pk)
          db.exec(
            "INSERT INTO leaf_search_index(rowid, title, content) VALUES ($1, $2, $3)",
            pk, sanitize(title.to_s), sanitize(searchable_content.to_s),
          )
        else
          db.exec("DELETE FROM leaf_search_index WHERE rowid = ?", pk)
          db.exec(
            "INSERT INTO leaf_search_index(rowid, title, content) VALUES (?, ?, ?)",
            pk, sanitize(title.to_s), sanitize(searchable_content.to_s),
          )
        end
      end
    end

    private def remove_from_search_index : Nil
      Marten::DB::Connection.default.open do |db|
        if Searchable.postgres?
          db.exec("DELETE FROM leaf_search_index WHERE rowid = $1", pk)
        else
          db.exec("DELETE FROM leaf_search_index WHERE rowid = ?", pk)
        end
      end
    end

    # Strip every HTML tag from text destined for the index. Mirrors
    # Rails Leaf::Searchable#sanitize_for_index (which uses
    # Rails::Html::FullSanitizer.new.sanitize).
    private def sanitize(text : String) : String
      ::Books::HtmlScrubber.strip_all(text)
    end
  end
end
