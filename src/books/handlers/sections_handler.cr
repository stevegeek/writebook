module Books
  # Sections — plain-text divider/heading leaves of a Book.
  class SectionsNewHandler < Marten::Handlers::Schema
    include ::Accounts::AuthenticationHelpers

    before_dispatch :require_authentication

    schema SectionSchema
    template_name "sections/new.html"

    def context
      super.merge({"book" => book})
    end

    def process_valid_schema
      target_book = book
      return respond("Book not found", status: 404) if target_book.nil?

      title = schema.validated_data["title"].as(String).strip
      body = schema.validated_data["body"]?.as(String?) || ""
      theme = schema.validated_data["theme"]?.as(String?).presence

      Marten::DB::Connection.default.transaction do
        section = Leafables::Section.create!(body: body, theme: theme)
        Leaf.create!(book: target_book, leafable: section, title: title, status: "active")
      end

      redirect(Marten.routes.reverse("books:show", id: target_book.pk))
    end

    private def book : Book?
      Book.get(pk: params["book_id"]?)
    end
  end

  # Markdown export for a single section leaf. Mirrors Rails'
  # `app/views/leafables/show.md.erb`.
  class SectionsMarkdownHandler < Marten::Handler
    include ::Accounts::AuthenticationHelpers

    def get
      leaf = Leaf.get(pk: params["id"]?)
      return respond("Not found", status: 404) if leaf.nil?

      section = leaf.leafable.try(&.as?(Leafables::Section))
      return respond("Not a section", status: 404) if section.nil?

      book = leaf.book!
      unless book.published || book.accessable?(current_user) || book.editable?(current_user)
        return respond("Not found", status: 404)
      end

      url = "#{request.scheme}://#{request.host}#{Marten.routes.reverse("sections:show", id: leaf.pk!)}"
      content = String.build do |io|
        io << "---\n"
        io << "title: " << %("#{leaf.title.to_s.gsub('"', "\\\"")}") << '\n'
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

    before_dispatch :require_authentication

    def post
      target_book = book
      return head :not_found if target_book.nil?
      return head :forbidden unless target_book.editable?(current_user)

      created_leaf = nil
      Marten::DB::Connection.default.transaction do
        section = Leafables::Section.create!(body: "")
        created_leaf = Leaf.create!(book: target_book, leafable: section, title: "New section", status: "active")
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

  # Sections render their plain-text body in a `page--section` div (with an
  # optional `theme--dark` modifier). Mirrors the Rails LeafablesController
  # dispatch for sections in `app/views/leafables/show.html.erb`.
  class SectionsShowHandler < Marten::Handler
    include ::Accounts::AuthenticationHelpers

    def get
      leaf = Leaf.get(pk: params["id"]?)
      return respond("Not found", status: 404) if leaf.nil?

      section = leaf.leafable.try(&.as?(Leafables::Section))
      return respond("Not a section", status: 404) if section.nil?

      book = leaf.book!
      active_leaves = book.leaves.filter(status: "active")
      prev_leaf = active_leaves.filter(position_score__lt: leaf.position_score!).order("-position_score").first
      next_leaf = active_leaves.filter(position_score__gt: leaf.position_score!).order(:position_score).first
      leaves = active_leaves.order(:position_score, :id).to_a

      request.cookies.set(
        "reading_progress_#{book.pk}",
        leaf.id.to_s,
        expires: 1.year.from_now,
        path: "/"
      )

      edit_url = Marten.routes.reverse("sections:edit", id: leaf.pk!)
      render("sections/show.html", context: {
        leaf:          leaf,
        section:       section,
        book:          book,
        leaves:        leaves,
        previous_leaf: prev_leaf,
        next_leaf:     next_leaf,
        signed_in:     signed_in?,
        editable:      book.editable?(current_user),
        edit_url:      edit_url,
        search:        request.query_params["search"]?.try(&.strip).presence,
      })
    end
  end

  class SectionsEditHandler < Marten::Handlers::Schema
    include ::Accounts::AuthenticationHelpers

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
      book = target_leaf.book!
      active = book.leaves.filter(status: "active")
      context[:book] = book
      context[:leaves] = active.order(:position_score, :id).to_a
      context[:editable] = book.editable?(current_user)
      # Sections render through pages:show in reading mode (Rails uses the same      #
      # leafable_slug_path for both); the edit-mode toggle on a section's edit page  #
      # therefore points at pages:show.                                              #
      context[:edit_url] = Marten.routes.reverse("sections:edit", id: target_leaf.pk!)
      context[:show_url] = Marten.routes.reverse("pages:show", id: target_leaf.pk!)
      context[:being_edited_stream] = "leaf_#{target_leaf.pk!}_being_edited"
      context[:edits_count] = target_leaf.edits.count
      context[:previous_leaf] = active.filter(position_score__lt: target_leaf.position_score!).order("-position_score").first
      context[:next_leaf] = active.filter(position_score__gt: target_leaf.position_score!).order(:position_score).first
    end

    private def broadcast_being_edited(target_leaf : Leaf) : Nil
      user = current_user
      return if user.nil?
      stream = "leaf_#{target_leaf.pk!}_being_edited"
      MartenTurbo.broadcast_append_to(
        stream,
        target: "leaf_#{target_leaf.pk!}_being_edited",
        partial: "leaves/_being_edited_by.turbo_stream.html",
        locals: {"leaf" => target_leaf, "user" => user},
      )
    end

    private def leaf : Leaf?
      Leaf.get(pk: params["id"]?)
    end

    private def section : Leafables::Section?
      leaf.try(&.leafable.try(&.as?(Leafables::Section)))
    end
  end
end
