module Accounts
  # Per-user editor/reader access to a Book. Sits in `accounts` because
  # the relationship is anchored on User; the `book` FK crosses into the
  # books app.
  class Access < Marten::Model
    field :id, :big_int, primary_key: true, auto: true
    field :user, :many_to_one, to: Accounts::User, related: :accesses, on_delete: :cascade
    field :book, :many_to_one, to: Books::Book, related: :accesses, on_delete: :cascade
    field :level, :string, max_size: 16, blank: false, null: false  # editor | reader

    with_timestamp_fields

    db_unique_constraint :access_user_book_unique, field_names: [:user_id, :book_id]
    db_index :access_book_idx, field_names: [:book_id]

    scope :reader { filter(level: "reader") }
    scope :editor { filter(level: "editor") }

    def editor?
      level == "editor"
    end

    def reader?
      level == "reader"
    end
  end
end
