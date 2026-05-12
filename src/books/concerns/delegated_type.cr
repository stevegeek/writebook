# Rails-style `delegated_type :leafable, types: [...]` on top of Marten's
# `field :leafable, :polymorphic, to: [...]`.
#
# Marten's polymorphic field already auto-generates per-type sugar
# accessors named `<type>_<field>` (so `page_leafable`, `section_leafable`,
# `picture_leafable`). Rails' `delegated_type` exposes them under the
# shorter `<type>` form (`leaf.page`, `leaf.section`, `leaf.picture`).
# This macro emits the rename plus matching `?` predicates so the model
# class definition reads exactly like the Rails original:
#
#   class Leaf < Marten::Model
#     field :leafable, :polymorphic, to: [Page, Section, Picture]
#     delegated_type :leafable, types: [Page, Section, Picture]
#   end
#
# Candidate for a `marten-delegated-type` shard once the shape settles.
module Books
  module DelegatedType
    macro delegated_type(field, types)
      {% type_list = types.is_a?(ArrayLiteral) ? types : types.expressions %}
      {% for type in type_list %}
        {% short_name = type.stringify.split("::").last.underscore.id %}

        def {{ short_name }}
          {{ short_name }}_{{ field.id }}
        end

        def {{ short_name }}? : ::Bool
          {{ short_name }}_{{ field.id }}?
        end
      {% end %}
    end
  end
end
