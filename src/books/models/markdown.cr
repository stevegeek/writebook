module Books
  # The custom ActionText::Markdown analog. Polymorphic `record` lets one
  # Markdown row attach to any model that uses `has_markdown :name`.
  #
  # Currently only Page uses this (as Writebook does); extending the
  # polymorphic target list to more models is a one-line change.
  class Markdown < Marten::Model
    include Marten::Template::CanDefineTemplateAttributes

    field :id, :big_int, primary_key: true, auto: true
    # Polymorphic to: must list at least two types — Crystal would otherwise
    # type the array as Array(SingleType.class), which doesn't unify with
    # the macro's expected Array(Marten::DB::Model.class). Add the second
    # type when a real second markdown-host arrives; for now Section is a
    # harmless placeholder (Section never actually has a markdown body).
    field :record, :polymorphic, to: [Books::Leafables::Page, Books::Leafables::Section], related: :markdowns
    field :name, :string, max_size: 64, blank: false, null: false
    field :content, :text, blank: true, null: false, default: ""

    with_timestamp_fields

    template_attributes :id, :name, :content, :to_html, :created_at, :updated_at

    db_index :markdown_record_idx, field_names: [:record_type, :record_id, :name]

    def to_html : String
      MarkdownRenderer.render(content || "")
    end

    def plain_text : String
      # Strip tags from rendered HTML to produce a plain-text projection.
      # ASCII-only; sufficient for FTS indexing.
      rendered = to_html
      rendered.gsub(/<[^>]+>/, " ").gsub(/\s+/, " ").strip
    end
  end
end
