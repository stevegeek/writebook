# Leafable-aware template helpers, centralising the 3-way `leafable_type`
# branching that templates repeated everywhere. Mirrors Rails' polymorphic
# URL helpers (`page_path` / `section_path` / `picture_path` via
# `polymorphic_path`) and the `leafable_name`-driven CSS class suffix.
#
# `{% leafable_url leaf %}`       → "/pages/5" / "/sections/3" / "/pictures/7"
# `{% leafable_edit_url leaf %}`  → "/pages/5/edit" etc.
# `{% leafable_class leaf %}`     → "page" / "section" / "picture"
#
# Each tag takes a `Books::Leaf` (whose polymorphic `leafable` decides which
# branch fires) or a concrete `Books::Leafables::*` instance.
module LeafableHelpers
  extend self

  def leafable_url(leafable : Books::Leafables::Page) : String
    Marten.routes.reverse("pages:show", id: leafable.pk!)
  end

  def leafable_url(leafable : Books::Leafables::Section) : String
    Marten.routes.reverse("sections:show", id: leafable.pk!)
  end

  def leafable_url(leafable : Books::Leafables::Picture) : String
    Marten.routes.reverse("pictures:show", id: leafable.pk!)
  end

  def leafable_edit_url(leafable : Books::Leafables::Page) : String
    Marten.routes.reverse("pages:edit", id: leafable.pk!)
  end

  def leafable_edit_url(leafable : Books::Leafables::Section) : String
    Marten.routes.reverse("sections:edit", id: leafable.pk!)
  end

  def leafable_edit_url(leafable : Books::Leafables::Picture) : String
    Marten.routes.reverse("pictures:edit", id: leafable.pk!)
  end

  def leafable_class(leafable : Books::Leafables::Page) : String
    "page"
  end

  def leafable_class(leafable : Books::Leafables::Section) : String
    "section"
  end

  def leafable_class(leafable : Books::Leafables::Picture) : String
    "picture"
  end

  # Leaf-receiving overloads — unwrap the polymorphic target via a case dispatch
  # so callers can just pass `{% leafable_url leaf %}` from a template. Crystal's
  # case-narrowing doesn't propagate through a yield, so each method inlines its
  # own switch.

  def leafable_url(leaf : Books::Leaf) : String
    case target = leaf.leafable
    when Books::Leafables::Page    then leafable_url(target)
    when Books::Leafables::Section then leafable_url(target)
    when Books::Leafables::Picture then leafable_url(target)
    else
      raise "Leaf #{leaf.pk} has no recognised leafable (got #{target.class})"
    end
  end

  def leafable_edit_url(leaf : Books::Leaf) : String
    case target = leaf.leafable
    when Books::Leafables::Page    then leafable_edit_url(target)
    when Books::Leafables::Section then leafable_edit_url(target)
    when Books::Leafables::Picture then leafable_edit_url(target)
    else
      raise "Leaf #{leaf.pk} has no recognised leafable (got #{target.class})"
    end
  end

  def leafable_class(leaf : Books::Leaf) : String
    case target = leaf.leafable
    when Books::Leafables::Page    then leafable_class(target)
    when Books::Leafables::Section then leafable_class(target)
    when Books::Leafables::Picture then leafable_class(target)
    else
      raise "Leaf #{leaf.pk} has no recognised leafable (got #{target.class})"
    end
  end
end

# Shared base for the three leafable_* tags. Each subclass passes a method-name
# symbol — kept as a string here because the FilterExpression.resolve flow.
abstract class LeafableHelpers::LeafableTagBase < Marten::Template::Tag::Base
  include Marten::Template::Tag::CanSplitSmartly

  @leaf_expr : Marten::Template::FilterExpression

  def initialize(parser : Marten::Template::Parser, source : String)
    parts = split_smartly(source)
    if parts.size != 2
      raise Marten::Template::Errors::InvalidSyntax.new(
        "Malformed #{tag_name} tag: expected exactly one argument (the leaf)"
      )
    end
    @leaf_expr = Marten::Template::FilterExpression.new(parts[1])
  end

  abstract def tag_name : String
  abstract def call(leaf : Books::Leaf) : String

  def render(context : Marten::Template::Context) : String
    raw = @leaf_expr.resolve(context).raw
    leaf = raw.as?(Books::Leaf)
    if leaf.nil?
      raise Marten::Template::Errors::UnsupportedValue.new(
        "#{tag_name} tag expects a Books::Leaf, got #{raw.class}"
      )
    end
    call(leaf)
  end
end

class LeafableHelpers::LeafableUrlTag < LeafableHelpers::LeafableTagBase
  def tag_name : String
    "leafable_url"
  end

  def call(leaf : Books::Leaf) : String
    LeafableHelpers.leafable_url(leaf)
  end
end

class LeafableHelpers::LeafableEditUrlTag < LeafableHelpers::LeafableTagBase
  def tag_name : String
    "leafable_edit_url"
  end

  def call(leaf : Books::Leaf) : String
    LeafableHelpers.leafable_edit_url(leaf)
  end
end

class LeafableHelpers::LeafableClassTag < LeafableHelpers::LeafableTagBase
  def tag_name : String
    "leafable_class"
  end

  def call(leaf : Books::Leaf) : String
    LeafableHelpers.leafable_class(leaf)
  end
end

# Note: tags are registered from Books::App#setup (alongside dom_id) so they
# survive marten-turbo's own tag-registration pass that runs at app setup time.
