module Accounts
  # User role enum/predicates. Roles are stored as a string in the
  # `accounts_user.role` column. Two roles for now: "member" and "administrator".
  module Role
    ROLES = %w[member administrator]

    def member?
      role == "member"
    end

    def administrator?
      role == "administrator"
    end

    # Mirrors Rails User::Role#can_administer? — a named alias of
    # `administrator?` that reads better at the callsite.
    def can_administer? : Bool
      administrator?
    end
  end
end
