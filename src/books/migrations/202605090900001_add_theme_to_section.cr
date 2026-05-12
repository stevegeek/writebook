# Adds theme column to books_section to match Rails (light/dark theming
# for divider sections). Rails schema has `t.string "theme"` (nullable, no
# default); we mirror that.
class Migration::Books::V202605090900001 < Marten::Migration
  def plan
    add_column :books_section, :theme, :string, max_size: 32, null: true
  end
end
