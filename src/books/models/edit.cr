module Books
  # Revision/trash record for a leaf. Stores a snapshot pointer to the
  # leafable that *was* attached at the time of the edit (so we can show
  # diff history), and an event type ("revision" | "trash").
  class Edit < Marten::Model
    include Marten::Template::CanDefineTemplateAttributes
    include DelegatedType

    field :id, :big_int, primary_key: true, auto: true
    field :leaf, :many_to_one, to: Books::Leaf, related: :edits, on_delete: :cascade
    field :leafable, :polymorphic, to: [Books::Leafables::Page, Books::Leafables::Section, Books::Leafables::Picture]
    field :event, :string, max_size: 16, blank: false, null: false  # revision | trash

    with_timestamp_fields

    delegated_type :leafable, types: [Books::Leafables::Page, Books::Leafables::Section, Books::Leafables::Picture]

    template_attributes :id, :leaf_id, :leafable_type, :event, :created_at, :updated_at,
      :page, :page?, :section, :section?, :picture, :picture?,
      :previous_edit, :next_edit

    db_index :edit_leaf_idx, field_names: [:leaf_id, :created_at]

    def self.revisions
      filter(event: "revision")
    end

    def self.trashes
      filter(event: "trash")
    end

    # Mirrors Rails' Edit#previous / #next — the chronologically prior/next
    # edit for the same leaf. Used by the edits/show.html prev/next nav.
    def previous_edit : Edit?
      ts = created_at
      return nil if ts.nil?
      Edit.filter(leaf_id: leaf_id, created_at__lt: ts).order("-created_at").first
    end

    def next_edit : Edit?
      ts = created_at
      return nil if ts.nil?
      Edit.filter(leaf_id: leaf_id, created_at__gt: ts).order(:created_at).first
    end
  end
end
