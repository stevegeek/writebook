require "marten_delegated_type"

module Books
  class Leaf < Marten::Model
    include Marten::Template::CanDefineTemplateAttributes
    include MartenDelegatedType
    include Positionable
    include Editable
    include Searchable

    # Searchable concern callbacks declared here (not inside the concern's
    # macro included) to guarantee they register — see gotchas.md.
    after_create_commit :create_in_search_index
    after_update_commit :update_in_search_index
    after_delete_commit :remove_from_search_index

    field :id, :big_int, primary_key: true, auto: true
    field :book, :many_to_one, to: Books::Book, related: :leaves, on_delete: :cascade
    field :leafable, :polymorphic, to: [Books::Leafables::Page, Books::Leafables::Section, Books::Leafables::Picture]
    field :position_score, :float, blank: false, null: false, default: 0.0
    field :status, :string, max_size: 16, blank: false, null: false, default: "active"
    field :title, :string, max_size: 255, blank: false, null: false

    with_timestamp_fields

    delegated_type :leafable, types: [Books::Leafables::Page, Books::Leafables::Section, Books::Leafables::Picture]

    template_attributes :id, :book_id, :title, :status, :position_score, :leafable_type,
      :page, :page?, :section, :section?, :picture, :picture?,
      :position_as_percentage,
      :created_at, :updated_at

    db_index :leaf_book_status_idx, field_names: [:book_id, :status]

    scope :active { filter(status: "active") }
    scope :trashed { filter(status: "trashed") }
    scope :with_leafables { prefetch(:leafable) }

    def active? : Bool
      status == "active"
    end

    def trashed? : Bool
      status == "trashed"
    end

    def all_positioned_siblings
      book!.leaves.filter(status: "active").order(:position_score, :id)
    end

    # Drives the `--progress` CSS variable on the bookmark indicator
    # (mirrors Rails' Positionable#position_as_percentage).
    def position_as_percentage : Float64
      total = all_positioned_siblings.count
      return 0.0 if total.zero?
      ordinal = other_positioned_siblings.filter(position_score__lt: position_score!).count + 1
      100.0 * ordinal.to_f / total.to_f
    end

    def trashed!
      update!(status: "trashed")
    end

    def slug : String
      derived = title.to_s.downcase.gsub(/[^a-z0-9]+/, "-").strip('-')
      derived.empty? ? "-" : derived
    end
  end
end
