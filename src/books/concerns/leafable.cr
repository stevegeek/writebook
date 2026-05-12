module Books
  # Mixin for the three concrete leafable types (Page, Section, Picture).
  #
  # Each leafable knows how to:
  #   - return its searchable text content (`searchable_content`),
  #   - return a markable string for export (`markable`),
  #   - identify its short type name (`leafable_name`).
  module Leafable
    TYPES = %w[page section picture]

    def searchable_content : String?
      nil
    end

    def markable : String
      ""
    end

    def leafable_name : String
      self.class.name.split("::").last.downcase
    end
  end
end
