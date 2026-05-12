module Books
  # Pages — markdown-bodied leaves of a Book. New page flow:
  #   1. Create empty Page row (so it has a pk)
  #   2. Save Markdown row pointing at the page (via has_markdown :body)
  #   3. Create Leaf wrapping the Page, attached to the Book
  class PagesNewHandler < Marten::Handlers::Schema
    include ::Accounts::AuthenticationHelpers

    before_dispatch :require_authentication

    schema PageSchema
    template_name "pages/new.html"

    def context
      super.merge({"book" => book})
    end

    def process_valid_schema
      target_book = book
      return respond("Book not found", status: 404) if target_book.nil?

      title = schema.validated_data["title"].as(String).strip
      body = schema.validated_data["body"]?.as(String?) || ""

      Marten::DB::Connection.default.transaction do
        page = Leafables::Page.create!
        page.body = body  # uses has_markdown setter — saves a Markdown row
        Leaf.create!(book: target_book, leafable: page, title: title, status: "active")
      end

      redirect(Marten.routes.reverse("books:show", id: target_book.pk))
    end

    private def book : Book?
      Book.get(pk: params["book_id"]?)
    end
  end

  class PagesShowHandler < Marten::Handler
    include ::Accounts::AuthenticationHelpers

    def get
      leaf = Leaf.get(pk: params["id"]?)
      return respond("Not found", status: 404) if leaf.nil?

      page = leaf.leafable.try(&.as?(Leafables::Page))
      return respond("Not a page", status: 404) if page.nil?

      book = leaf.book!
      active_leaves = book.leaves.filter(status: "active")
      prev_leaf = active_leaves.filter(position_score__lt: leaf.position_score!).order("-position_score").first
      next_leaf = active_leaves.filter(position_score__gt: leaf.position_score!).order(:position_score).first
      leaves = active_leaves.order(:position_score, :id).to_a

      # Record reading progress cookie — used by the bookmark resume feature
      request.cookies.set(
        "reading_progress_#{book.pk}",
        leaf.id.to_s,
        expires: 1.year.from_now,
        path: "/"
      )

      rendered = page.body.try(&.to_html) || ""
      edit_url = Marten.routes.reverse("pages:edit", id: leaf.pk!)
      render("pages/show.html", context: {
        leaf:          leaf,
        page:          page,
        book:          book,
        leaves:        leaves,
        previous_leaf: prev_leaf,
        next_leaf:     next_leaf,
        rendered_html: rendered,
        signed_in:     signed_in?,
        editable:      book.editable?(current_user),
        edit_url:      edit_url,
        search:        request.query_params["search"]?.try(&.strip).presence,
      })
    end
  end

  # Markdown export for a single page leaf. Mirrors Rails'
  # `app/views/leafables/show.md.erb`.
  class PagesMarkdownHandler < Marten::Handler
    include ::Accounts::AuthenticationHelpers
    include ::Accounts::UrlHelpers

    def get
      leaf = Leaf.get(pk: params["id"]?)
      return respond("Not found", status: 404) if leaf.nil?

      page = leaf.leafable.try(&.as?(Leafables::Page))
      return respond("Not a page", status: 404) if page.nil?

      book = leaf.book!
      unless book.published || book.accessable?(current_user) || book.editable?(current_user)
        return respond("Not found", status: 404)
      end

      url = absolute_url("pages:show", id: leaf.pk!)
      content = String.build do |io|
        io << "---\n"
        io << "title: " << %("#{leaf.title.to_s.gsub('"', "\\\"")}") << '\n'
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

    before_dispatch :require_authentication

    def post
      target_book = book
      return head :not_found if target_book.nil?
      return head :forbidden unless target_book.editable?(current_user)

      created_leaf = nil
      Marten::DB::Connection.default.transaction do
        page = Leafables::Page.create!
        page.body = ""
        created_leaf = Leaf.create!(book: target_book, leafable: page, title: "New page", status: "active")
      end

      leaf = created_leaf.not_nil!

      if request.turbo?
        turbo_stream("books/leafable_create.turbo_stream.html", {"leaf" => leaf})
      else
        redirect(Marten.routes.reverse("books:show", id: target_book.pk))
      end
    end

    private def book : Book?
      Book.get(pk: params["book_id"]?)
    end
  end

  class PagesEditHandler < Marten::Handlers::Schema
    include ::Accounts::AuthenticationHelpers
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
      book = target_leaf.book!
      active = book.leaves.filter(status: "active")
      context[:book] = book
      context[:leaves] = active.order(:position_score, :id).to_a
      context[:editable] = book.editable?(current_user)
      context[:edit_url] = Marten.routes.reverse("pages:edit", id: target_leaf.pk!)
      context[:show_url] = Marten.routes.reverse("pages:show", id: target_leaf.pk!)
      context[:being_edited_stream] = "leaf_#{target_leaf.pk!}_being_edited"
      context[:edits_count] = target_leaf.edits.count
      context[:previous_leaf] = active.filter(position_score__lt: target_leaf.position_score!).order("-position_score").first
      context[:next_leaf] = active.filter(position_score__gt: target_leaf.position_score!).order(:position_score).first
    end

    private def leaf : Leaf?
      Leaf.get(pk: params["id"]?)
    end

    private def page : Leafables::Page?
      leaf.try(&.leafable.try(&.as?(Leafables::Page)))
    end
  end
end
