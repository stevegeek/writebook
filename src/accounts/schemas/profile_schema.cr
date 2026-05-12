module Accounts
  # Schema for editing a user's own profile. Password is optional —
  # if the field is left blank we skip the password update.
  class ProfileSchema < Marten::Schema
    field :name, :string, max_size: 255, required: true
    field :email_address, :string, max_size: 255, required: true
    field :password, :string, max_size: 255, required: false
  end
end
