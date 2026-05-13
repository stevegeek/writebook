require "sanitize"

module Books
  # Faithful port of Rails Writebook's `app/models/html_scrubber.rb`, which
  # extends Loofah's `PermitScrubber` with a small list of extra tags. The
  # Marten port can't use Loofah (Ruby-only), so we build the same policy
  # on top of the `straight-shoota/sanitize` shard — a Crystal wrapper
  # around the same underlying engine (libxml2) Loofah uses.
  #
  # Three call shapes mirror Rails' usage:
  #
  #   - `sanitize_content(html)`       → markdown-rendered HTML for display.
  #                                      Allowed tags = Rails DEFAULT_ALLOWED_TAGS
  #                                      + Writebook HtmlScrubber extras.
  #   - `sanitize_search_result(html)` → FTS5 highlight snippets — only
  #                                      `<mark>` survives (mirrors Rails
  #                                      `SearchesHelper#sanitize_search_result`).
  #   - `strip_all(text)`              → strip every tag (mirrors Rails
  #                                      `Rails::Html::FullSanitizer`, used
  #                                      by `Leaf::Searchable#sanitize_for_index`).
  module HtmlScrubber
    extend self

    # Verbatim port of rails-html-sanitizer's
    # `Rails::Html::SafeListSanitizer::DEFAULT_ALLOWED_TAGS`. The Marten
    # whitelist is intentionally a subset of straight-shoota's `.common`
    # baseline — sticking to Rails' published list keeps the attack surface
    # identical to the Rails port byte-for-byte.
    RAILS_ALLOWED_TAGS = %w[
      a abbr acronym address b big blockquote br cite code dd del dfn div
      dl dt em h1 h2 h3 h4 h5 h6 hr i img ins kbd li mark ol p pre samp
      small span strong sub sup time tt ul var
    ]

    # Verbatim port of `Rails::Html::SafeListSanitizer::DEFAULT_ALLOWED_ATTRIBUTES`.
    # Rails applies the same attribute allowlist across every allowed tag —
    # so do we.
    RAILS_ALLOWED_ATTRIBUTES = %w[
      abbr alt cite class datetime height href lang name src title width xml:lang
    ]

    # Verbatim port of `writebook-rails/app/models/html_scrubber.rb` extras.
    EXTRA_TAGS = %w[
      audio details summary iframe options table tbody td th thead tr video
      source mark
    ]

    # Rails' default attribute list doesn't include `id` or `style`, but
    # Loofah accepts them via a separate scrubbed-attribute path (style
    # values go through a CSS scrubber). Rails Writebook tests assert that
    # `<div id="test" style="...">` survives, so we add both here — and
    # accept that style values are not CSS-sanitized in the port. Same
    # property as Rails so long as the source markdown is HTML-escaped by
    # the renderer for attribute values; CSS sanitization is documented as
    # not supported by `straight-shoota/sanitize`.
    EXTRA_PASSTHROUGH_ATTRIBUTES = %w[id style]

    def sanitize_content(html : String) : String
      content_sanitizer.process(html)
    end

    def sanitize_search_result(html : String) : String
      mark_sanitizer.process(html)
    end

    def strip_all(text : String) : String
      text_sanitizer.process(text).strip.gsub(/\s+/, " ")
    end

    @@content_sanitizer : Sanitize::Policy::HTMLSanitizer?
    @@mark_sanitizer : Sanitize::Policy::HTMLSanitizer?
    @@text_sanitizer : Sanitize::Policy::Text?

    private def content_sanitizer : Sanitize::Policy::HTMLSanitizer
      @@content_sanitizer ||= build_content_sanitizer
    end

    # Constructs the policy directly from the Rails tag/attribute lists —
    # no `HTMLSanitizer.common` baseline. Each allowed tag receives the
    # full attribute allowlist (Rails' Loofah PermitScrubber is global,
    # not per-tag).
    private def build_content_sanitizer : Sanitize::Policy::HTMLSanitizer
      attrs_per_tag = (RAILS_ALLOWED_ATTRIBUTES + EXTRA_PASSTHROUGH_ATTRIBUTES).to_set
      accepted = {} of String => Set(String)
      (RAILS_ALLOWED_TAGS + EXTRA_TAGS).each do |tag|
        accepted[tag] = attrs_per_tag.dup
      end

      s = Sanitize::Policy::HTMLSanitizer.new(accepted_attributes: accepted)
      # Rails Loofah doesn't inject `rel="nofollow"` from PermitScrubber —
      # that's a separate `TargetScrubber`. Match Rails default behavior.
      s.add_rel_nofollow = false
      s.add_rel_noopener = false
      # Rails doesn't filter class values; straight-shoota strips `class=""`
      # entirely unless `valid_classes` has matches. Add a permissive regex
      # that accepts any single CSS identifier (covers tartrazine's
      # `language-*` and the project's own utility classes).
      s.valid_classes << /.+/
      s
    end

    private def mark_sanitizer : Sanitize::Policy::HTMLSanitizer
      @@mark_sanitizer ||= begin
        s = Sanitize::Policy::HTMLSanitizer.new(
          accepted_attributes: {"mark" => Set(String).new} of String => Set(String)
        )
        s.add_rel_nofollow = false
        s.add_rel_noopener = false
        s
      end
    end

    private def text_sanitizer : Sanitize::Policy::Text
      @@text_sanitizer ||= Sanitize::Policy::Text.new
    end
  end
end
