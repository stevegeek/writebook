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

      rows = [] of {Int64, String?, String?}
      Marten::DB::Connection.default.open do |db|
        if book_id
          db.query sql, book_id, cleaned do |rs|
            rs.each { rows << {rs.read(Int64), rs.read(String?), rs.read(String?)} }
          end
        else
          db.query sql, cleaned do |rs|
            rs.each { rows << {rs.read(Int64), rs.read(String?), rs.read(String?)} }
          end
        end
      end

      assemble_results(rows)
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

      rows = [] of {Int64, String?, String?}
      Marten::DB::Connection.default.open do |db|
        db.query(sql, args: args) do |rs|
          rs.each { rows << {rs.read(Int64), rs.read(String?), rs.read(String?)} }
        end
      end

      assemble_results(rows)
    end

    # Bulk-load the matched Leaf rows with their leafables prefetched, then
    # zip them back together with their highlight strings in result order.
    # Collapses 2N per-result queries (Leaf.get per row + lazy leafable per
    # template access) into 1 leaves SELECT + 1 leafable prefetch per type.
    private def self.assemble_results(
      rows : Array({Int64, String?, String?}),
    ) : Array(NamedTuple(leaf: Leaf, title_match: String?, content_match: String?))
      return [] of NamedTuple(leaf: Leaf, title_match: String?, content_match: String?) if rows.empty?

      ids = rows.map(&.[0])
      by_id = Leaf.filter(pk__in: ids).prefetch(:leafable).index_by(&.pk!)

      rows.compact_map do |(leaf_id, title_match, content_match)|
        leaf = by_id[leaf_id]?
        next nil if leaf.nil?
        {
          leaf:          leaf,
          title_match:   title_match.try { |s| ::Books::HtmlScrubber.sanitize_search_result(s) },
          content_match: content_match.try { |s| ::Books::HtmlScrubber.sanitize_search_result(s) },
        }
      end
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
      # UPDATE-then-INSERT-on-miss, mirroring Rails Leaf::Searchable
      # (writebook-rails/app/models/leaf/searchable.rb). Saves one RTT
      # per leaf save (UPDATE = 1 stmt vs the previous DELETE + INSERT = 2),
      # which matters on managed Postgres where every round-trip is
      # ~10ms over tailscale.
      title_text = sanitize(title.to_s)
      content_text = sanitize(searchable_content.to_s)
      Marten::DB::Connection.default.open do |db|
        updated = if Searchable.postgres?
                    db.exec(
                      "UPDATE leaf_search_index SET title = $1, content = $2 WHERE rowid = $3",
                      title_text, content_text, pk,
                    )
                  else
                    db.exec(
                      "UPDATE leaf_search_index SET title = ?, content = ? WHERE rowid = ?",
                      title_text, content_text, pk,
                    )
                  end
        # On miss (no existing row for this rowid yet — e.g. a leaf
        # that didn't have indexable content at create-time but now
        # does), fall back to INSERT.
        next if updated.rows_affected > 0
        if Searchable.postgres?
          db.exec(
            "INSERT INTO leaf_search_index(rowid, title, content) VALUES ($1, $2, $3)",
            pk, title_text, content_text,
          )
        else
          db.exec(
            "INSERT INTO leaf_search_index(rowid, title, content) VALUES (?, ?, ?)",
            pk, title_text, content_text,
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
