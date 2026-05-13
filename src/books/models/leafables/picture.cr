module Books::Leafables
  # Image leaf. The actual file lives in an `Attachment` row pointed at
  # by `Attachment.record = picture` with `name = "image"` and an optional
  # `large` variant computed at upload time.
  class Picture < Marten::Model
    include ::Books::Leafable
    include ::Books::SignedGlobalId::HasIt

    field :id, :big_int, primary_key: true, auto: true
    field :caption, :string, max_size: 1024, blank: true, null: true

    with_timestamp_fields

    template_attributes :id, :caption, :created_at, :updated_at

    def markable : String
      caption || ""
    end
  end
end
