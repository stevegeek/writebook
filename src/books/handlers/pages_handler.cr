module Books
  # Pages — markdown-bodied leaves of a Book. New page flow:
  #   1. Create empty Page row (so it has a pk)
  #   2. Save Markdown row pointing at the page (via has_markdown :body)
  #   3. Create Leaf wrapping the Page, attached to the Book
  class PagesNewHandler < Marten::Handlers::Schema
    include ::Accounts::AuthenticationHelpers
    include BookScoped

    before_dispatch :require_authentication
    before_dispatch :require_book
    before_dispatch :ensure_editable

    schema PageSchema
    template_name "pages/new.html"

    def context
      super.merge({"book" => book!})
    end

    def process_valid_schema
      target_book = book!
      title = schema.validated_data["title"].as(String).strip
      body = schema.validated_data["body"]?.as(String?) || ""

      Marten::DB::Connection.default.transaction do
        page = Leafables::Page.create!
        page.body = body  # uses has_markdown setter — saves a Markdown row
        target_book.press(page, title: title)
      end

      redirect(Marten.routes.reverse("books:show", id: target_book.pk))
    end
  end

  class PagesShowHandler < Marten::Handler
    include ::Accounts::AuthenticationHelpers
    include LeafScoped

    before_dispatch :require_leaf

    def get
      target_leaf = leaf!
      page = target_leaf.leafable.try(&.as?(Leafables::Page))
      return respond("Not a page", status: 404) if page.nil?

      target_book = book!

      # Record reading progress cookie — used by the bookmark resume feature
      request.cookies.set(
        "reading_progress_#{target_book.pk}",
        target_leaf.id.to_s,
        expires: 1.year.from_now,
        path: "/"
      )

      rendered = page.to_safe_html
      render("pages/show.html", context: {
        leaf:          target_leaf,
        page:          page,
        book:          target_book,
        leaves:        sorted_active_leaves,
        previous_leaf: previous_leaf,
        next_leaf:     next_leaf,
        rendered_html: rendered,
        signed_in:     signed_in?,
        editable:      target_book.editable?(current_user),
        edit_url:      Marten.routes.reverse("pages:edit", id: target_leaf.pk!),
        search:        request.query_params["search"]?.try(&.strip).presence,
      })
    end
  end

  # Markdown export for a single page leaf. Mirrors Rails'
  # `app/views/leafables/show.md.erb`.
  class PagesMarkdownHandler < Marten::Handler
    include ::Accounts::AuthenticationHelpers
    include ::Accounts::UrlHelpers
    include LeafScoped

    before_dispatch :require_leaf

    def get
      target_leaf = leaf!
      page = target_leaf.leafable.try(&.as?(Leafables::Page))
      return respond("Not a page", status: 404) if page.nil?

      target_book = book!
      unless target_book.published || target_book.accessable?(current_user) || target_book.editable?(current_user)
        return respond("Not found", status: 404)
      end

      url = absolute_url("pages:show", id: target_leaf.pk!)
      content = String.build do |io|
        io << "---\n"
        io << "title: " << %("#{target_leaf.title.to_s.gsub('"', "\\\"")}") << '\n'
        io << "url: " << %("#{url}") << '\n'
        io << "---\n\n"
        io << page.markable
      end
      respond(content, content_type: "text/markdown", status: 200)
    end
  end

  # Inline-create endpoint. POSTed by the "+ Page" button in the TOC toolbar.
  # Creates an empty Page+Leaf and responds with a turbo-stream that appends
  # the inline edit row to the :leaves frame, mirroring Rails leafables/create.
  class PagesCreateHandler < Marten::Handler
    include ::Accounts::AuthenticationHelpers
    include MartenTurbo::Handlers::Concerns::Streamable
    include BookScoped

    before_dispatch :require_authentication
    before_dispatch :require_book
    before_dispatch :ensure_editable

    def post
      target_book = book!

      # Title / body / position carry over from a regular form submit (Rails
      # leafables_controller passes them through). Blanks fall back to the
      # inline-create defaults — the user can rename later in the edit UI.
      # `request.data` raises on no/garbled body (e.g. the inline "+ Page"
      # turbo POST sends none); treat that as no params provided.
      submitted_title, submitted_body, position = begin
        data = request.data
        {
          data["title"]?.try(&.to_s).presence,
          data["body"]?.try(&.to_s),
          data["position"]?.try(&.to_s).try(&.to_i?),
        }
      rescue
        {nil, nil, nil}
      end

      created_leaf = nil
      Marten::DB::Connection.default.transaction do
        page = Leafables::Page.create!
        page.body = submitted_body || ""
        created_leaf = target_book.press(page, title: submitted_title || "New page")
      end

      leaf = created_leaf.not_nil!
      # Mirrors Rails LeafablesController#position_new_leaf — when the form
      # supplies a `position`, the just-created leaf jumps there. Rails'
      # acts_as_list position param is 1-indexed; Marten's Positionable
      # move_to_position is 0-indexed (see positionable_spec). Translate.
      leaf.move_to_position(position - 1) if position

      if request.turbo?
        turbo_stream("books/leafable_create.turbo_stream.html", {"leaf" => leaf})
      else
        redirect(Marten.routes.reverse("books:show", id: target_book.pk))
      end
    end
  end

  class PagesEditHandler < Marten::Handlers::Schema
    include ::Accounts::AuthenticationHelpers
    include LeafScoped
    include LeafEditingBroadcast

    before_dispatch :require_authentication
    before_render :inject_book_context

    schema PageSchema
    template_name "pages/edit.html"

    def context
      super.merge({"leaf" => leaf, "page" => page})
    end

    def initial_data
      target_leaf = leaf
      target_page = page
      if target_leaf && target_page
        {"title" => target_leaf.title.to_s, "body" => target_page.body.try(&.content) || ""}
      else
        super
      end
    end

    def process_valid_schema
      target_leaf = leaf
      target_page = page
      return respond("Not found", status: 404) if target_leaf.nil? || target_page.nil?

      title = schema.validated_data["title"].as(String).strip
      body = schema.validated_data["body"]?.as(String?) || ""

      Marten::DB::Connection.default.transaction do
        target_page.body = body
        target_leaf.update!(title: title)
      end

      # Real-time "user X is editing" broadcast — mirrors Rails'
      # LeafablesController#broadcast_being_edited_indicator. Sends the
      # `_being_edited_by` partial to the per-leaf channel that all other
      # viewers of this leaf are subscribed to via the indicator partial.
      broadcast_being_edited(target_leaf)

      # Autosaves are PATCHy — Rails responds with `head :no_content` on the
      # html format. Marten's Schema handler ordinarily redirects to a
      # success URL after a valid POST. Detect the autosave / fetch case
      # (request from `@rails/request.js` sends Accept: text/html and
      # X-Requested-With: XMLHttpRequest) and return 204 so the editor stays
      # on the edit page rather than navigating away mid-typing.
      if request.headers["X-Requested-With"]? == "XMLHttpRequest" || request.turbo?
        return head :no_content
      end

      redirect(Marten.routes.reverse("books:show", id: target_leaf.book!.pk))
    end

    private def inject_book_context : Nil
      target_leaf = leaf
      return if target_leaf.nil?
      context[:book] = book!
      context[:leaves] = sorted_active_leaves
      context[:editable] = book!.editable?(current_user)
      context[:edit_url] = Marten.routes.reverse("pages:edit", id: target_leaf.pk!)
      context[:show_url] = Marten.routes.reverse("pages:show", id: target_leaf.pk!)
      context[:being_edited_stream] = "leaf_#{target_leaf.pk!}_being_edited"
      context[:edits_count] = target_leaf.edits.count
      context[:previous_leaf] = previous_leaf
      context[:next_leaf] = next_leaf
    end

    private def page : Leafables::Page?
      leaf.try(&.leafable.try(&.as?(Leafables::Page)))
    end
  end
end
