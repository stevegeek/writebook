module Accounts
  # Subclass of MartenAuth::User. The base class provides:
  #   - `email` (unique, validated email format)
  #   - `password` (string, holds the bcrypt hash, not raw text)
  #   - `created_at`, `updated_at`
  #   - instance methods: `set_password(raw)`, `check_password(raw)`,
  #     `set_unusable_password`, `session_auth_hash`
  #   - class methods: `get_by_natural_key(email)`, `.authenticate(...)`
  #
  # Writebook-specific extras live on top: a display `name`, a `role`
  # enum-by-string, and an `active` deactivation flag.
  class User < MartenAuth::User
    include Role
    include MartenSignedId::ModelMixin
    include Transferable

    field :name, :string, max_size: 255, blank: false, null: false
    field :role, :string, max_size: 32, blank: false, null: false, default: "member"
    field :active, :bool, default: true

    template_attributes :id, :name, :email, :role, :active, :created_at, :updated_at

    scope :active { filter(active: true) }
    scope :ordered { order(:name) }
    scope :member        { filter(role: "member") }
    scope :administrator { filter(role: "administrator") }

    # Convenience for the common "look up an active user by id, return nil
    # if not found or deactivated" pattern that handlers used to spell as
    # `User.filter(active: true).get(id: <raw_id>)`. Accepts any id type
    # Marten's `get` will (Int32 / Int64 / String / nil) and returns nil
    # for nil input.
    def self.active_get(id) : User?
      return nil if id.nil?
      active.get(id: id)
    end

    # `active_get!` raises Marten::DB::Errors::RecordNotFound if no active
    # user matches. Mirrors Marten's `get!` semantics.
    def self.active_get!(id) : User
      active.get!(id: id)
    end

    # Mirrors Rails User#after_create grant_access_to_everyone_books — every
    # newly-joined user is auto-granted reader access to every book that has
    # `everyone_access: true`.
    after_create :grant_access_to_everyone_books

    # Books accessible to this user via Access M2M. Cross-app reference.
    def books
      Books::Book.filter(accesses__user_id: id)
    end

    # Mirrors Rails User#current?, which compares against the fiber-local
    # `Current.user`. Marten has no fiber-local equivalent — pass the
    # session's current user in explicitly. AuthenticationHelpers#current?
    # wraps this for handler callers; templates consume a pre-computed
    # boolean from the context.
    def current?(other : User?) : Bool
      return false if other.nil?
      pk == other.pk
    end

    def deactivate
      Marten::DB::Connection.default.transaction do
        # Anonymise the email so the slot can be re-used and so the now-deactivated
        # user can't sign in (set_unusable_password also blocks check_password).
        set_unusable_password
        update!(
          active: false,
          email: deactivated_email,
        )
      end
    end

    private def deactivated_email
      addr = email
      return nil if addr.nil?
      addr.gsub("@", "-deactivated-#{UUID.random}@")
    end

    private def grant_access_to_everyone_books : Nil
      Books::Book.with_everyone_access.each do |book|
        # Skip if an Access already exists (defensive — should never collide on a fresh create).
        next if Access.filter(user_id: id, book_id: book.pk).exists?
        Access.create!(user_id: id, book_id: book.pk, level: "reader")
      end
    end
  end
end
