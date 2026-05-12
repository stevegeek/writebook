# Rebuild leaf_search_index as a regular (content-bearing) FTS5 table.
# The previous `content=''` (contentless) variant disallows UPDATE entirely
# and requires the original values to be supplied for DELETE — fragile for
# a write-through index synced via post-commit callbacks. A regular FTS5
# table stores the content alongside the index and supports straightforward
# INSERT / DELETE / UPDATE.
class Migration::Books::V202605080500001 < Marten::Migration
  def plan
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
