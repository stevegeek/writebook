module Accounts
  # Singleton tenant — Once-style. `Accounts::Account.first!` is the only account.
  class Account < Marten::Model
    field :id, :big_int, primary_key: true, auto: true
    field :name, :string, max_size: 255, blank: false, null: false
    field :join_code, :string, max_size: 64, blank: false, null: false
    field :custom_styles, :text, blank: true, null: true

    with_timestamp_fields

    template_attributes :id, :name, :join_code, :custom_styles, :created_at, :updated_at

    def self.create_with_defaults!(name : String) : Account
      create!(name: name, join_code: Random::Secure.hex(8))
    end

    def reset_join_code! : Nil
      update!(join_code: Random::Secure.hex(8))
    end
  end
end
