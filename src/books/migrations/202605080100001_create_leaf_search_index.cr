# Hand-written migration: SQLite FTS5 virtual table backing Leaf full-text
# search (`Searchable`). Marten's auto-migration can't model FTS5 virtual
# tables, so this is a raw SQL operation.
class Migration::Books::V202605080100001 < Marten::Migration
  def plan
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
  end
end
