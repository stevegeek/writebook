module Books
  # Unified storage row — replaces Active Storage's Blob + Attachment +
  # VariantRecord trio. One row per file (original or variant).
  #
  # `record` is polymorphic over the three host types that own attachments:
  # `Book` (cover), `Picture` (image), and `Markdown` (uploads).
  #
  # Variants are pre-computed at upload time (rather than on-demand): a
  # variant row points at its original via `variant_of` self-FK, with a
  # discriminator in `variation_kind` (e.g., "large").
  #
  # `name` is the attribute name on the host: e.g., "cover" on Book,
  # "image" on Picture, "uploads" on Markdown. Multiple attachments with
  # the same name on the same record represent a `has_many_attached`-style
  # collection.
  class Attachment < Marten::Model
    field :id, :big_int, primary_key: true, auto: true
    field :record, :polymorphic, to: [Books::Book, Books::Leafables::Picture, Books::Markdown], related: :attachments
    field :name, :string, max_size: 64, blank: false, null: false
    field :file, :file, blank: false, null: false, upload_to: "attachments"
    field :variant_of, :many_to_one, to: Books::Attachment, related: :variants, blank: true, null: true, on_delete: :cascade
    field :variation_kind, :string, max_size: 64, blank: true, null: true
    field :content_type, :string, max_size: 128, blank: true, null: true
    field :byte_size, :big_int, blank: true, null: true
    field :slug, :string, max_size: 255, blank: true, null: true, unique: true

    with_timestamp_fields

    template_attributes :id, :name, :file, :variation_kind, :content_type, :byte_size, :created_at, :updated_at

    db_index :attachment_record_idx, field_names: [:record_type, :record_id, :name]

    def original?
      variant_of_id.nil?
    end

    def variant?
      !original?
    end
  end
end
