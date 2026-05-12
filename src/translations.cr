# Translation popovers for form fields. Mirrors Writebook's
# `app/helpers/translations_helper.rb` — a globe-icon popover next to inputs
# that asks "what is this field" in 6 languages, side-by-side.
#
# The strings live in `config/locales/<locale>.yml` under the
# `field_labels.*` namespace. Marten's I18n integration loads them
# automatically (configured via `config.i18n.available_locales`); the tag
# iterates the available locales and pulls each translation via
# `I18n.translate(..., locale: ...)`.
#
# Use as a custom template tag:
#
#   {% translation_button "email_address" %}
#
# Available keys mirror Rails Writebook: book_author, book_subtitle,
# book_title, custom_styles, email_address, password, picture_caption,
# transfer_session, transfer_session_self, user_name, update_password.
module Translations
  # Display flag per locale code. Order is preserved from Rails Writebook.
  LOCALE_FLAGS_BY_STRING = {
    "en" => "🇺🇸",
    "es" => "🇪🇸",
    "fr" => "🇫🇷",
    "hi" => "🇮🇳",
    "de" => "🇩🇪",
    "pt" => "🇧🇷",
  } of String => String

  # Render the popover HTML for a given key. Mirrors Rails'
  # `translation_button(:foo)` helper output.
  def self.render_button(key : String) : String
    String.build do |io|
      io << %(<div class="position-relative" data-controller="popover")
      io << %( data-action="keydown.esc->popover#close click@document->popover#closeOnClickOutside")
      io << %( data-popover-orientation-top-class="popover-orientation-top">)
      io << %(<button type="button" class="btn" tabindex="-1" data-action="popover#toggle">)
      io << %(<img src="/assets/images/globe.svg" width="20" height="20" role="presentation" class="color-icon" alt="">)
      io << %(<span class="for-screen-reader">Translate</span>)
      io << %(</button>)
      io << %(<dialog class="lanuage-list-menu popover shadow" data-popover-target="menu">)
      io << %(<dl class="language-list">)

      LOCALE_FLAGS_BY_STRING.each do |locale_str, flag|
        translation = I18n.with_locale(locale_str) do
          I18n.translate("field_labels.#{key}")
        end

        io << %(<dt>) << flag << %(</dt>)
        io << %(<dd class="margin-none">)
        translation.each_char do |c|
          case c
          when '<' then io << "&lt;"
          when '>' then io << "&gt;"
          when '&' then io << "&amp;"
          when '"' then io << "&quot;"
          else          io << c
          end
        end
        io << %(</dd>)
      end

      io << %(</dl></dialog></div>)
    end
  end
end

# Custom Marten template tag implementing `{% translation_button "key" %}`.
class Translations::ButtonTag < Marten::Template::Tag::Base
  include Marten::Template::Tag::CanSplitSmartly

  def initialize(parser : Marten::Template::Parser, source : String)
    parts = split_smartly(source)
    if parts.size < 2
      raise Marten::Template::Errors::InvalidSyntax.new(
        "Malformed translation_button tag: one argument required (the translation key)"
      )
    end
    @key_expression = Marten::Template::FilterExpression.new(parts[1])
  end

  def render(context : Marten::Template::Context) : String
    key = @key_expression.resolve(context).to_s
    Translations.render_button(key)
  end
end

Marten::Template::Tag.register("translation_button", Translations::ButtonTag)
