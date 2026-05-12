module Books
  class PageSchema < Marten::Schema
    field :title, :string, max_size: 255, required: true
    field :body, :string, required: false  # markdown source; allowed to be empty
  end
end
