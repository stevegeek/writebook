# `has_markdown :body` on a model declares a named markdown attribute
# stored in the polymorphic `Books::Markdown` table.
#
# Adds three methods to the host:
#   - `body` — fetch (or autobuild) the Markdown row for this attribute.
#   - `body?` — Bool indicating whether a non-empty body exists.
#   - `body=(content : String)` — set the markdown content (saves immediately).
#
# Usage:
#
#   module Books::Leafables
#     class Page < Marten::Model
#       field :id, :big_int, primary_key: true, auto: true
#       has_markdown :body
#     end
#   end
class Marten::Model
  macro has_markdown(name)
    {% klass = @type %}

    def {{ name.id }} : ::Books::Markdown
      m = ::Books::Markdown
        .filter(record_type: {{ klass.stringify }}, record_id: pk)
        .filter(name: {{ name.id.stringify }})
        .first
      if m
        m
      else
        ::Books::Markdown.new.tap do |new_md|
          new_md.record = self
          new_md.name = {{ name.id.stringify }}
          new_md.content = ""
        end
      end
    end

    def {{ name.id }}? : Bool
      m = ::Books::Markdown
        .filter(record_type: {{ klass.stringify }}, record_id: pk)
        .filter(name: {{ name.id.stringify }})
        .first
      !m.nil? && !m.content.try(&.empty?)
    end

    def {{ name.id }}=(content : String) : Nil
      m = {{ name.id }}
      m.content = content
      m.save!
    end
  end
end
