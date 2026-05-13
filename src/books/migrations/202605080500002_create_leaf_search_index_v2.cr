# Re-create leaf_search_index after the v1 (contentless) table was dropped
# in 202605080500001. SQLite only — postgres path is a no-op.
class Migration::Books::V202605080500002 < Marten::Migration
  def plan
    return unless Marten::DB::Connection.default.scheme == "sqlite3"
    execute(
      "CREATE VIRTUAL TABLE leaf_search_index USING fts5(title, content, tokenize='porter unicode61 remove_diacritics 2')",
      "DROP TABLE leaf_search_index",
    )
  end
end
