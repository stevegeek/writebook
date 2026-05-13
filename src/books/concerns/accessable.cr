module Books
  # Per-user access controls for `Book`. Includes class-level scope helpers
  # (`accessable_or_published`) and instance methods (`editable?`,
  # `accessable?`, `update_access`). Cross-app references to `Accounts::User`
  # and `Accounts::Access`.
  module Accessable
    macro included
      scope :with_everyone_access { filter(everyone_access: true) }
      # Note: `scope :published` lives on the host model (Book) — it isn't an
      # access-control concept, it's a book-state one. Rails Writebook keeps
      # it on the Book class itself for the same reason.

      # Books visible to the given user (or to no-one if anonymous): direct
      # accesses OR published. Marten's QuerySet has no `union` operator,
      # so we OR the two predicates with a single combined filter via Q.
      # Parameterised + returns a typed queryset — kept as a class method
      # rather than a scope.
      def self.accessable_or_published(user : ::Accounts::User?) : Marten::DB::Query::Set(self)
        if user
          uid = user.id
          filter { q(accesses__user_id: uid) | q(published: true) }.distinct
        else
          published
        end
      end
    end

    def accessable?(user : ::Accounts::User?) : Bool
      return false if user.nil?
      ::Accounts::Access.filter(book_id: pk, user_id: user.id).exists?
    end

    def editable?(user : ::Accounts::User?) : Bool
      return false if user.nil?
      return true if user.administrator?
      a = access_for(user)
      !a.nil? && a.editor?
    end

    def access_for(user : ::Accounts::User?) : ::Accounts::Access?
      return nil if user.nil?
      ::Accounts::Access.filter(book_id: pk, user_id: user.id).first
    end

    def update_access(editor_ids : Array(Int64), reader_ids : Array(Int64)) : Nil
      editors = editor_ids.to_set
      readers = (everyone_access ? ::Accounts::User.active.pluck(:id).flatten.map(&.as(Int64)) : reader_ids).to_set
      all = editors + readers

      Marten::DB::Connection.default.transaction do
        ::Accounts::Access.filter(book_id: pk).exclude(user_id__in: all.to_a).delete
        all.each do |uid|
          level = editors.includes?(uid) ? "editor" : "reader"
          existing = ::Accounts::Access.filter(book_id: pk, user_id: uid).first
          if existing
            existing.update!(level: level) unless existing.level == level
          else
            ::Accounts::Access.create!(book_id: pk, user_id: uid, level: level)
          end
        end
      end
    end
  end
end
