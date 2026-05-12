module Accounts
  # Schema for the per-tenant custom-CSS editor.
  class CustomStylesSchema < Marten::Schema
    field :custom_styles, :string, max_size: 65_535, required: false
  end
end
