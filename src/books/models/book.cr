module Books
  class Book < Marten::Model
    include Marten::Template::CanDefineTemplateAttributes
    include Accessable

    THEMES = %w[black blue green magenta orange violet white]

    field :id, :big_int, primary_key: true, auto: true
    field :title, :string, max_size: 255, blank: false, null: false
    field :subtitle, :string, max_size: 255, blank: true, null: true
    field :author, :string, max_size: 255, blank: true, null: true
    field :published, :bool, default: false
    field :slug, :string, max_size: 255, blank: false, null: false
    field :theme, :string, max_size: 32, default: "blue"
    field :everyone_access, :bool, default: false

    with_timestamp_fields

    template_attributes :id, :title, :subtitle, :author, :published, :slug, :theme, :everyone_access, :created_at, :updated_at

    before_validation :populate_slug

    private def populate_slug : Nil
      self.slug = SluggableHelpers.populate_if_blank(slug, title.to_s)
    end

    scope :ordered { order(:title) }

    # Mirrors Rails' `enum :theme, %w[...], suffix: true` — generates one
    # filter scope AND one predicate per theme: Book.black_theme, .blue_theme,
    # …; book.black_theme?, .blue_theme?, ….
    {% for theme in %w[black blue green magenta orange violet white] %}
      scope :{{theme.id}}_theme { filter(theme: {{theme}}) }

      def {{theme.id}}_theme? : Bool
        theme == {{theme}}
      end
    {% end %}

    # Aggregate Markdown for export — concatenates each leafable's `markable`
    # output across the book's active leaves in display order.
    def markable : String
      leaves
        .filter(status: "active")
        .order(:position_score, :id)
        .compact_map { |leaf| leaf_markable(leaf) }
        .join("\n\n")
    end

    private def leaf_markable(leaf : Leaf) : String?
      target = leaf.leafable
      case target
      when Leafables::Page
        target.markable
      when Leafables::Section
        target.markable
      when Leafables::Picture
        target.markable
      else
        nil
      end
    end
  end
end
