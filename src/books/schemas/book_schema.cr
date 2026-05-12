module Books
  class BookSchema < Marten::Schema
    field :title, :string, max_size: 255, required: true
    field :subtitle, :string, max_size: 255, required: false
    field :author, :string, max_size: 255, required: false
    field :theme, :string, max_size: 32, required: false
    field :everyone_access, :bool, required: false

    validate :default_theme

    private def default_theme
      theme_val = validated_data["theme"]?.as?(String)
      if theme_val.nil? || theme_val.empty? || !Book::THEMES.includes?(theme_val)
        validated_data["theme"] = "blue"
      end
    end
  end
end
