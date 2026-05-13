module Books
  # The Marten equivalent of Writebook's ActionText::Markdown row.
  # Polymorphic `record` lets one Markdown row attach to any model
  # that calls `has_markdown :name` (provided that model is in the `to:`
  # list below).
  #
  # Render pipeline + `to_html` / `plain_text` come from
  # `MartenText::Renderable`. The two host-supplied hooks
  # (lightbox-wrapped images, heading anchor markup) are registered in
  # `Books::App` at app load.
  #
  # Why the `to:` list lives on the host rather than the shard:
  # Marten's polymorphic field needs the target type list at compile
  # time, so the host owns the concrete Markdown model. Add more
  # leafables here as they grow markdown bodies.
  class Markdown < Marten::Model
    include Marten::Template::CanDefineTemplateAttributes
    include ::MartenText::Renderable
    include MartenGlobalId::ModelMixin

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

    # Look up the Markdown row attached to `record` under `attribute_name`.
    # Mirrors Rails' `record.safe_markdown_attribute(attribute_name)` from
    # writebook-rails' `lib/rails_ext/action_text_has_markdown.rb`. Used by
    # the upload handler: an editor-driven file attach knows the host
    # record (via signed gid) + the attribute name (e.g. "body"), and
    # needs the Markdown row to attach files to.
    def self.safe_attribute(record : Marten::DB::Model, attribute_name : String) : Markdown?
      filter(record_type: record.class.name, record_id: record.pk!)
        .filter(name: attribute_name)
        .first
    end
  end
end
