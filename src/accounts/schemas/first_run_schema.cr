module Accounts
  # Mirrors Rails: first-run takes only `name`, `email_address`, `password`
  # for the first administrator user. The Account is named with the
  # hard-coded `FirstRun::ACCOUNT_NAME` constant ("Writebook").
  class FirstRunSchema < Marten::Schema
    field :name, :string, max_size: 255, required: true
    field :email_address, :string, max_size: 255, required: true
    field :password, :string, max_size: 255, required: true
  end
end
