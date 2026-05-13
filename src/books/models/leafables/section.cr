module Books::Leafables
  # Plain-text divider/heading between pages. `body` is a literal string,
  # not Markdown. `theme` is "dark" or nil (= light), used by the TOC card
  # and the show/edit container to pick a CSS modifier (matches Rails).
  class Section < Marten::Model
    include ::Marten::Template::CanDefineTemplateAttributes
    include ::Books::Leafable
    include ::MartenGlobalId::ModelMixin

    field :id, :big_int, primary_key: true, auto: true
    field :body, :text, blank: true, null: true
    field :theme, :string, max_size: 32, blank: true, null: true

    with_timestamp_fields

    template_attributes :id, :body, :body_html, :theme, :created_at, :updated_at

    # Rails sections render their body via `simple_format` — wrap paragraphs
    # split by blank lines in <p>, single newlines in <br>. Mirror that here
    # so the TOC card can render via {{ leaf.section.body_html|safe }}.
    def body_html : String
      raw = body.to_s
      return "" if raw.empty?
      escaped = raw
        .gsub('&', "&amp;")
        .gsub('<', "&lt;")
        .gsub('>', "&gt;")
        .gsub('"', "&quot;")
      paragraphs = escaped.split(/\n{2,}/)
      paragraphs.map { |p| "<p>#{p.gsub('\n', "<br>")}</p>" }.join
    end

    def searchable_content : String?
      body
    end

    def markable : String
      body || ""
    end
  end
end
