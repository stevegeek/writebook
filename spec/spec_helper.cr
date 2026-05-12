ENV["MARTEN_ENV"] = "test"

require "spec"
require "../src/project"
require "marten/spec"

require "./support/**"

# Marten::Spec uses `schema_editor.sync_models` (not migrations) to build the
# test schema, so hand-written FTS5 virtual-table migrations don't run. The
# Leaf model's after_*_commit callbacks INSERT/DELETE on `leaf_search_index`,
# which would crash with "no such table" in every model spec that touches a
# Leaf. Create the FTS5 table once before the suite to match what migrations
# would produce in dev/prod (mirrors 202605080500002_create_leaf_search_index_v2).
Spec.before_suite do
  Marten::DB::Connection.default.open do |db|
    db.exec("DROP TABLE IF EXISTS leaf_search_index")
    db.exec(
      "CREATE VIRTUAL TABLE leaf_search_index USING fts5(" \
      "title, content, tokenize='porter unicode61 remove_diacritics 2')"
    )
  end
end

# Marten::Spec.flush_databases truncates model tables but doesn't know about
# the FTS5 virtual table. Wipe it ourselves so rows from previous specs don't
# trip uniqueness/constraint issues in the next one.
Spec.after_each do
  Marten::DB::Connection.default.open do |db|
    db.exec("DELETE FROM leaf_search_index")
  end
end
