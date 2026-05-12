require "../spec_helper"

# Ports `writebook-rails/test/lib/markdown_renderer_test.rb`.
#
# In the Marten port, the Rails `MarkdownRenderer` class has been
# decomposed into:
#   - `MartenText::Renderer` — the shared markd+tartrazine pipeline
#     in the `marten-text` shard (`lib/marten_text/`).
#   - host-supplied `image_wrapper` and `heading_anchor` hooks
#     configured in `Books::App` (`src/books/app.cr`) that emit the
#     Writebook-specific lightbox/anchor markup.
#
# The Rails test only asserts duplicate-heading IDs; that maps directly
# to `MartenText::Renderer.render` because the heading hook receives
# already-deduped ids.
describe "Markdown rendering (port of Rails MarkdownRenderer)" do
  describe "duplicate heading IDs" do
    it "generates unique IDs for duplicate headers" do
      content = MartenText::Renderer.render(
        "# Header 1\n\n## Duplicated Header\n\n### Duplicated header\n\n"
      )

      # The Writebook heading_anchor hook (configured in Books::App) emits
      # `id="..."` rather than Rails' single-quoted `id='...'`, but the
      # invariant under test is the same: the second occurrence of the
      # same slug gets a `-2` suffix.
      content.should contain(%(id="duplicated-header"))
      content.should contain(%(id="duplicated-header-2"))
    end

    it "wraps each <img> via the configured image_wrapper hook" do
      # Rails' MarkdownRenderer also wrapped images in a lightbox anchor;
      # the Marten port moves that to the Books::App image_wrapper hook.
      html = MartenText::Renderer.render(%(![cat](/u.png "kitten")))
      html.should contain(%(<img src="/u.png" alt="cat">))
      # Writebook's hook adds the lightbox stimulus attributes.
      html.should contain("lightbox")
    end

    it "highlights fenced code blocks with a known language" do
      # Rails: MarkdownRenderer.build used Rouge for highlighting.
      # Marten port: tartrazine, registered inside the shared renderer.
      html = MartenText::Renderer.render("```ruby\nputs :hi\n```\n")
      html.should contain("<pre")
      html.should_not eq(Markd.to_html("```ruby\nputs :hi\n```\n"))
    end
  end

  pending "Trix/ActionText embed resolution" do
    # FIXME(porting gap): Rails' MarkdownRenderer integrated with
    # ActionText to resolve attachment SGIDs inline. The Marten port has
    # no Trix/ActionText layer — Markdown bodies are plain `text` columns,
    # and attachments live on a polymorphic `Books::Attachment` row
    # without inline embeds. No equivalent to test.
  end
end
