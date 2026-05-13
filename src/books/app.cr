require "marten_text"
require "marten_storages"

# Books app — the content domain. Owns Book, Leaf, Edit, Markdown,
# Leafables (Page/Section/Picture), and Attachment (storage), plus the
# concerns and helpers for those.
require "./html_scrubber"
require "./signed_global_id"
require "./concerns/**"
require "./models/**"
require "./schemas/**"
require "./handlers/**"
require "./routes"

# Configure the markdown renderer with Writebook's UI markup. These two
# hooks used to be inline in the deleted MarkdownRenderer:
#
#   - image_wrapper: wraps each `<img>` in the lightbox-trigger anchor
#     so clicking an image pops it open (see _lightbox.html partial).
#   - heading_anchor: adds an id-based permalink anchor next to each
#     heading — the `.heading__link` styled "#" hover-anchor.
MartenText.configure do |c|
  c.image_wrapper = ->(url : String, alt : String, title : String?) {
    title_attr = (title && !title.empty?) ? %( title="#{title}") : ""
    %(<a#{title_attr} data-action="lightbox#open:prevent" data-lightbox-target="image" ) +
      %(data-lightbox-url-value="#{url}?disposition=attachment" href="#{url}">) +
      %(<img src="#{url}" alt="#{alt}"></a>)
  }
  c.heading_anchor = ->(level : String, text : String, id : String) {
    %(<#{level} id="#{id}">#{text} <a href="##{id}" class="heading__link" aria-hidden="true">#</a></#{level}>)
  }
end

module Books
  class App < Marten::App
    label "books"

    # Register the three leafable_* custom template tags. Naming doesn't
    # collide with anything in Marten core / marten-turbo, so registration
    # ordering doesn't matter here.
    def setup
      Marten::Template::Tag.register("leafable_url", LeafableHelpers::LeafableUrlTag)
      Marten::Template::Tag.register("leafable_edit_url", LeafableHelpers::LeafableEditUrlTag)
      Marten::Template::Tag.register("leafable_class", LeafableHelpers::LeafableClassTag)
    end
  end
end
