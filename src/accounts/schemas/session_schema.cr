module Accounts
  class SessionSchema < Marten::Schema
    field :email_address, :string, max_size: 255, required: true
    field :password, :string, max_size: 255, required: true
  end
end
