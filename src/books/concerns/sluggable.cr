module Books
  # Slug helpers shared between models that have a `slug` string field.
  # Mirrors the role of Rails' `Book::Sluggable` concern, but with a
  # different shape: Marten/Crystal's macro scoping doesn't let `macro
  # included` register host-class lifecycle callbacks (e.g.
  # `before_validation`) reliably — class-level constants like
  # `VALIDATION_CALLBACKS` resolve lexically inside the concern and
  # stay invisible from the host. So this module exposes helper methods
  # only; each host model declares its own `before_validation
  # :populate_slug` and calls these to do the work.
  module Sluggable
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
