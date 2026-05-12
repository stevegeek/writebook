module Books
  # Slug helpers shared between models that have a `slug` string field.
  # Concern macros that try to register Marten lifecycle callbacks (e.g.
  # `before_validation`) don't propagate cleanly through `macro included`
  # — Crystal's macro scoping looks up class-level constants like
  # `VALIDATION_CALLBACKS` lexically, and they aren't visible from inside
  # the concern module. So we expose helper methods only; each host model
  # declares its own `before_validation :populate_slug` and calls these.
  module SluggableHelpers
    extend self

    def parameterize(value : String) : String
      value
        .downcase
        .gsub(/[^a-z0-9]+/, "-")
        .strip('-')
    end

    def populate_if_blank(current_slug : String?, source_value : String, fallback : String = "untitled") : String
      return current_slug.not_nil! if !current_slug.nil? && !current_slug.empty?
      derived = parameterize(source_value)
      derived.empty? ? fallback : derived
    end
  end
end
