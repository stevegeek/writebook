module Accounts
  # Schema for user signup via the join-code flow.
  class UserSchema < Marten::Schema
    field :name, :string, max_size: 255, required: true
    field :email_address, :string, max_size: 255, required: true
    field :password, :string, max_size: 255, required: true
  end
end
