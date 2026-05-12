module Accounts
  # Schema for the admin role-toggle form on the users index.
  # Accepts a single "role" checkbox; absent checkbox = "member".
  class UserRoleSchema < Marten::Schema
    field :role, :string, max_size: 32, required: false
  end
end
