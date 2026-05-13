# Rebuild leaf_search_index. SQLite-only: switch from contentless FTS5 (no
# UPDATE) to a regular FTS5 table. Postgres' table from the v1 migration is
# already update-safe — nothing to do.
class Migration::Books::V202605080500001 < Marten::Migration
  def plan
    return unless Marten::DB::Connection.default.scheme == "sqlite3"
    execute(
      <<-SQL,
        DROP TABLE IF EXISTS leaf_search_index;
        CREATE VIRTUAL TABLE leaf_search_index USING fts5(
          title,
          content,
          tokenize='porter unicode61 remove_diacritics 2'
        );
      SQL
      <<-SQL
        DROP TABLE IF EXISTS leaf_search_index;
        CREATE VIRTUAL TABLE leaf_search_index USING fts5(
          title,
          content,
          content='',
          tokenize='porter unicode61 remove_diacritics 2'
        );
      SQL
    )
  end
end
