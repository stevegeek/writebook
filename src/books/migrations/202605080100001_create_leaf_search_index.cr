# Hand-written migration: full-text search backing for `Leaf` (`Searchable`).
# SQLite → FTS5 virtual table. PostgreSQL → plain table + GIN index on a
# generated tsvector column. Marten's auto-migrations can't model either.
class Migration::Books::V202605080100001 < Marten::Migration
  def plan
    case Marten::DB::Connection.default.scheme
    when "sqlite3"
      execute(
        <<-SQL,
          CREATE VIRTUAL TABLE leaf_search_index USING fts5(
            title,
            content,
            content='',
            tokenize='porter unicode61 remove_diacritics 2'
          )
        SQL
        "DROP TABLE leaf_search_index"
      )
    when "postgres"
      execute(
        <<-SQL,
          CREATE TABLE leaf_search_index (
            rowid BIGINT PRIMARY KEY,
            title TEXT,
            content TEXT,
            tsv TSVECTOR
              GENERATED ALWAYS AS (
                setweight(to_tsvector('english', coalesce(title, '')),   'A') ||
                setweight(to_tsvector('english', coalesce(content, '')), 'B')
              ) STORED
          )
        SQL
        "DROP TABLE leaf_search_index"
      )
      execute(
        "CREATE INDEX leaf_search_index_tsv_idx ON leaf_search_index USING GIN (tsv)",
        "DROP INDEX leaf_search_index_tsv_idx"
      )
    end
  end
end
