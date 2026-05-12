module Books
  # The Marten equivalent of Writebook's ActionText::Markdown row.
  # Polymorphic `record` lets one Markdown row attach to any model
  # that calls `has_markdown :name` (provided that model is in the `to:`
  # list below).
  #
  # Render pipeline + `to_html` / `plain_text` come from
  # `MartenMarkdown::Renderable`. The two host-supplied hooks
  # (lightbox-wrapped images, heading anchor markup) are registered in
  # `Books::App` at app load.
  #
  # Why the `to:` list lives on the host rather than the shard:
  # Marten's polymorphic field needs the target type list at compile
  # time, so the host owns the concrete Markdown model. Add more
  # leafables here as they grow markdown bodies.
  class Markdown < Marten::Model
    include Marten::Template::CanDefineTemplateAttributes
    include ::MartenMarkdown::Renderable

    field :id, :big_int, primary_key: true, auto: true
    # Polymorphic `to:` must list at least two types — Crystal would
    # otherwise type the array as Array(SingleType.class), which
    # doesn't unify with the macro's expected
    # Array(Marten::DB::Model.class). Section is a harmless placeholder
    # (Section doesn't actually have a markdown body) until a second
    # real markdown-host arrives.
    field :record, :polymorphic, to: [Books::Leafables::Page, Books::Leafables::Section], related: :markdowns
    field :name, :string, max_size: 64, blank: false, null: false
    field :content, :text, blank: true, null: false, default: ""

    with_timestamp_fields

    template_attributes :id, :name, :content, :to_html, :created_at, :updated_at

    db_index :markdown_record_idx, field_names: [:record_type, :record_id, :name]
  end
end
