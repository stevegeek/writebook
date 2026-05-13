module Books
  # Sections — plain-text divider/heading leaves of a Book.
  class SectionsNewHandler < Marten::Handlers::Schema
    include ::Accounts::AuthenticationHelpers
    include BookScoped

    before_dispatch :require_authentication
    before_dispatch :require_book
    before_dispatch :ensure_editable

    schema SectionSchema
    template_name "sections/new.html"

    def context
      super.merge({"book" => book!})
    end

    def process_valid_schema
      target_book = book!
      title = schema.validated_data["title"].as(String).strip
      body = schema.validated_data["body"]?.as(String?) || ""
      theme = schema.validated_data["theme"]?.as(String?).presence

      Marten::DB::Connection.default.transaction do
        section = Leafables::Section.create!(body: body, theme: theme)
        target_book.press(section, title: title)
      end

      redirect(Marten.routes.reverse("books:show", id: target_book.pk))
    end
  end

  # Markdown export for a single section leaf. Mirrors Rails'
  # `app/views/leafables/show.md.erb`.
  class SectionsMarkdownHandler < Marten::Handler
    include ::Accounts::AuthenticationHelpers
    include ::Accounts::UrlHelpers
    include LeafScoped

    before_dispatch :require_leaf

    def get
      target_leaf = leaf!
      section = target_leaf.leafable.try(&.as?(Leafables::Section))
      return respond("Not a section", status: 404) if section.nil?

      target_book = book!
      unless target_book.published || target_book.accessable?(current_user) || target_book.editable?(current_user)
        return respond("Not found", status: 404)
      end

      url = absolute_url("sections:show", id: target_leaf.pk!)
      content = String.build do |io|
        io << "---\n"
        io << "title: " << %("#{target_leaf.title.to_s.gsub('"', "\\\"")}") << '\n'
        io << "url: " << %("#{url}") << '\n'
        io << "---\n\n"
        io << section.markable
      end
      respond(content, content_type: "text/markdown", status: 200)
    end
  end

  # Inline-create endpoint. POSTed by the "+ Section" button in the TOC toolbar.
  class SectionsCreateHandler < Marten::Handler
    include ::Accounts::AuthenticationHelpers
    include MartenTurbo::Handlers::Concerns::Streamable
    include BookScoped

    before_dispatch :require_authentication
    before_dispatch :require_book
    before_dispatch :ensure_editable

    def post
      target_book = book!

      created_leaf = nil
      Marten::DB::Connection.default.transaction do
        section = Leafables::Section.create!(body: "")
        created_leaf = target_book.press(section, title: "New section")
      end

      leaf = created_leaf.not_nil!

      if request.turbo?
        turbo_stream("books/leafable_create.turbo_stream.html", {"leaf" => leaf})
      else
        redirect(Marten.routes.reverse("books:show", id: target_book.pk))
      end
    end
  end

  # Sections render their plain-text body in a `page--section` div (with an
  # optional `theme--dark` modifier). Mirrors the Rails LeafablesController
  # dispatch for sections in `app/views/leafables/show.html.erb`.
  class SectionsShowHandler < Marten::Handler
    include ::Accounts::AuthenticationHelpers
    include LeafScoped

    before_dispatch :require_leaf

    def get
      target_leaf = leaf!
      section = target_leaf.leafable.try(&.as?(Leafables::Section))
      return respond("Not a section", status: 404) if section.nil?

      target_book = book!

      request.cookies.set(
        "reading_progress_#{target_book.pk}",
        target_leaf.id.to_s,
        expires: 1.year.from_now,
        path: "/"
      )

      render("sections/show.html", context: {
        leaf:          target_leaf,
        section:       section,
        book:          target_book,
        leaves:        active_leaves.order(:position_score, :id).to_a,
        previous_leaf: previous_leaf,
        next_leaf:     next_leaf,
        signed_in:     signed_in?,
        editable:      target_book.editable?(current_user),
        edit_url:      Marten.routes.reverse("sections:edit", id: target_leaf.pk!),
        search:        request.query_params["search"]?.try(&.strip).presence,
      })
    end
  end

  class SectionsEditHandler < Marten::Handlers::Schema
    include ::Accounts::AuthenticationHelpers
    include LeafScoped
    include LeafEditingBroadcast

    before_dispatch :require_authentication
    before_render :inject_book_context

    schema SectionSchema
    template_name "sections/edit.html"

    def context
      super.merge({"leaf" => leaf, "section" => section})
    end

    def initial_data
      target_leaf = leaf
      target_section = section
      if target_leaf && target_section
        {
          "title" => target_leaf.title.to_s,
          "body"  => target_section.body.to_s,
          "theme" => target_section.theme.to_s,
        }
      else
        super
      end
    end

    def process_valid_schema
      target_leaf = leaf
      target_section = section
      return respond("Not found", status: 404) if target_leaf.nil? || target_section.nil?

      title = schema.validated_data["title"].as(String).strip
      body = schema.validated_data["body"]?.as(String?) || ""
      theme = schema.validated_data["theme"]?.as(String?).presence

      Marten::DB::Connection.default.transaction do
        target_section.update!(body: body, theme: theme)
        target_leaf.update!(title: title)
      end

      # Real-time "user X is editing" broadcast — see PagesEditHandler.
      broadcast_being_edited(target_leaf)

      if request.headers["X-Requested-With"]? == "XMLHttpRequest" || request.turbo?
        return head :no_content
      end

      redirect(Marten.routes.reverse("books:show", id: target_leaf.book!.pk))
    end

    private def inject_book_context : Nil
      target_leaf = leaf
      return if target_leaf.nil?
      context[:book] = book!
      context[:leaves] = active_leaves.order(:position_score, :id).to_a
      context[:editable] = book!.editable?(current_user)
      # Sections render through pages:show in reading mode (Rails uses the same      #
      # leafable_slug_path for both); the edit-mode toggle on a section's edit page  #
      # therefore points at pages:show.                                              #
      context[:edit_url] = Marten.routes.reverse("sections:edit", id: target_leaf.pk!)
      context[:show_url] = Marten.routes.reverse("pages:show", id: target_leaf.pk!)
      context[:being_edited_stream] = "leaf_#{target_leaf.pk!}_being_edited"
      context[:edits_count] = target_leaf.edits.count
      context[:previous_leaf] = previous_leaf
      context[:next_leaf] = next_leaf
    end

    private def section : Leafables::Section?
      leaf.try(&.leafable.try(&.as?(Leafables::Section)))
    end
  end
end
