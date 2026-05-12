module Books
  class SectionSchema < Marten::Schema
    field :title, :string, max_size: 255, required: true
    field :body, :string, required: false
    # Theme is "dark" or empty (= light). Rails matches: `t.string "theme"` (nullable).
    field :theme, :string, max_size: 32, required: false
  end
end
