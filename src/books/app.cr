# Books app — the content domain. Owns Book, Leaf, Edit, Markdown,
# Leafables (Page/Section/Picture), and Attachment (storage), plus the
# concerns and helpers for those.
require "./concerns/**"
require "./has_markdown"
require "./markdown_renderer"
require "./storage_helpers"
require "./models/**"
require "./schemas/**"
require "./handlers/**"
require "./routes"

module Books
  class App < Marten::App
    label "books"
  end
end
