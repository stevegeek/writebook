module Books::Leafables
  # Markdown-bodied page. The body lives in a separate `Markdown` row
  # pointed at by `Markdown.record = page`, accessed via the `has_markdown`
  # helper.
  class Page < Marten::Model
    include ::Marten::Template::CanDefineTemplateAttributes
    include ::Books::Leafable

    field :id, :big_int, primary_key: true, auto: true

    with_timestamp_fields

    template_attributes :id, :body, :html_preview, :word_count, :created_at, :updated_at

    has_markdown :body, model: ::Books::Markdown

    def searchable_content : String?
      body.try(&.plain_text)
    end

    def markable : String
      body.try(&.content) || ""
    end

    # Truncated HTML rendering for the leaf TOC card on books/show.
    # Mirrors Rails Page#html_preview which renders the first 1024 chars
    # of the markdown source through the regular renderer.
    def html_preview : String
      source = body.try(&.content) || ""
      ::MartenText::Renderer.render(source[0, 1024])
    end

    def word_count : Int32
      source = body.try(&.content) || ""
      source.scan(/\w+/).size
    end
  end
end
