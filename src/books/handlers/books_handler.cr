module Books
  # Shared cover-upload logic for BooksNewHandler / BooksEditHandler.
  #
  # Called after the Book record is saved. Handles:
  #   - `image` file param  → AttachmentHelpers.attach (creates/replaces cover)
  #   - `remove_cover=true` → deletes the existing cover attachment row + file
  #
  # Does nothing if neither param is present.
  module BookCoverUploadHelpers
    private def handle_cover_upload(book : Book) : Nil
      # remove_cover takes precedence over a new upload if both arrive together.
      if request.data["remove_cover"]?.try(&.to_s) == "true"
        existing = AttachmentHelpers.find_one(record: book, name: "cover")
        existing.delete if existing
        return
      end

      uploaded = request.data["image"]?.try(&.as?(Marten::HTTP::UploadedFile))
      return if uploaded.nil?

      # Replace any existing cover before attaching the new one.
      existing = AttachmentHelpers.find_one(record: book, name: "cover")
      existing.delete if existing

      AttachmentHelpers.attach(
        record: book,
        name: "cover",
        uploaded_file: uploaded,
        variants: {"thumbnail" => {max_dimension: 600}},
      )
    end
  end

  # Books CRUD. Index + show are public; new/create/edit/update/destroy require sign-in.

  class BooksIndexHandler < Marten::Handler
    include ::Accounts::AuthenticationHelpers

    def get
      # Mirror Rails' BooksController#ensure_index_is_not_empty: if anonymous and
      # no published books exist, force sign-in instead of rendering an empty page.
      if !signed_in? && !Book.published.exists?
        return redirect(Marten.routes.reverse("accounts:session_new"))
      end

      # Mirror Rails' Book.accessable_or_published.ordered: signed-in users see
      # books they have access to + published; anonymous users see only published.
      books = Book.accessable_or_published(current_user).order(:title).to_a

      # Bulk-load covers to avoid N+1 queries.
      covers = Attachment
        .filter(record_type: "Books::Book")
        .filter(name: "cover")
        .filter(variant_of_id: nil)
        .order("-created_at")
        .to_a

      # Latest cover per book keyed by Int64 pk.
      cover_map = {} of Int64 => Attachment
      covers.each do |att|
        rid = att.record_id
        bid = case rid
              when Int32 then rid.to_i64
              when Int64 then rid
              else next
              end
        cover_map[bid] ||= att
      end

      # Build NamedTuples so templates can access item.book and item.cover.
      book_entries = books.map do |book|
        pk = book.pk
        bid = case pk
              when Int32 then pk.to_i64
              when Int64 then pk
              else nil
              end
        cover = bid ? cover_map[bid]? : nil
        {book: book, cover: cover}
      end

      render("books/index.html", context: {
        book_entries: book_entries,
        signed_in:    signed_in?,
      })
    end
  end

  class BooksShowHandler < Marten::Handlers::RecordDetail
    include ::Accounts::AuthenticationHelpers

    model Book
    template_name "books/show.html"
    record_context_name "book"
    lookup_param "id"

    before_render :inject_extras

    private def inject_extras : Nil
      book = record
      leaves = book.leaves.filter(status: "active").order(:position_score, :id).to_a
      context[:leaves] = leaves
      context[:signed_in] = signed_in?
      context[:editable] = book.editable?(current_user)
      context[:cover] = AttachmentHelpers.find_one(record: book, name: "cover")
      # Used by books/publications/_publication.html for its own {% turbo_frame %}.
      context[:frame_id] = "book_publication_#{book.pk}"
    end
  end

  class BooksNewHandler < Marten::Handlers::RecordCreate
    include ::Accounts::AuthenticationHelpers
    include BookCoverUploadHelpers

    before_dispatch :require_authentication

    model Book
    schema BookSchema
    template_name "books/new.html"

    def success_url
      Marten.routes.reverse("books:show", id: record.not_nil!.pk!)
    end

    def process_valid_schema
      response = super
      book = record.not_nil!
      handle_cover_upload(book)
      apply_access_form(book)
      response
    end

    # Inject the user list + access defaults so _form.html can render the
    # books/accesses/_access partial. Mirrors Rails' BooksController#new
    # → set_users + locals: { creating_user: Current.user }.
    before_render :inject_form_extras

    private def inject_form_extras : Nil
      creating_user = current_user
      users = ::Accounts::User.active.ordered.to_a

      # On the new form, the creating user is the only editor/reader by default.
      uid = user_pk(creating_user)
      default_ids = uid.nil? ? ([] of Int64) : [uid]

      context[:users] = users
      context[:creating_user] = creating_user
      context[:editor_ids] = default_ids
      context[:reader_ids] = default_ids
      # No record yet during GET (new form), so no cover is injected.
    end

    # Mirror Rails' update_accesses: gather editor_ids[]/reader_ids[] from the
    # form (always including the current user) and persist via update_access.
    private def apply_access_form(book : Book) : Nil
      editor_ids = collect_ids("editor_ids")
      reader_ids = collect_ids("reader_ids")

      if (uid = user_pk(current_user))
        editor_ids << uid unless editor_ids.includes?(uid)
        reader_ids << uid unless reader_ids.includes?(uid)
      end

      book.update_access(editor_ids: editor_ids, reader_ids: reader_ids)
    end

    private def collect_ids(param_name : String) : Array(Int64)
      values = request.data.fetch_all(param_name, nil)
      return [] of Int64 if values.nil?
      values.compact_map do |v|
        str = v.to_s
        next nil if str.empty?
        Int64.new(str) rescue nil
      end
    end

    private def user_pk(user : ::Accounts::User?) : Int64?
      return nil if user.nil?
      raw = user.id
      case raw
      when Int32 then raw.to_i64
      when Int64 then raw
      else            nil
      end
    end
  end

  class BooksEditHandler < Marten::Handlers::RecordUpdate
    include ::Accounts::AuthenticationHelpers
    include BookCoverUploadHelpers

    before_dispatch :require_authentication
    before_dispatch :ensure_editable

    model Book
    schema BookSchema
    template_name "books/edit.html"
    record_context_name "book"
    lookup_param "id"

    def success_url
      Marten.routes.reverse("books:show", id: record.not_nil!.pk!)
    end

    def process_valid_schema
      response = super
      handle_cover_upload(record.not_nil!)
      response
    end

    # Inject the current cover attachment so _form.html can show/remove it.
    before_render :inject_cover

    private def inject_cover : Nil
      book = record
      return if book.nil?
      context[:cover] = AttachmentHelpers.find_one(record: book, name: "cover")
    end

    private def ensure_editable : Marten::HTTP::Response?
      book = record
      unless book.editable?(current_user)
        return head :forbidden
      end
      nil
    end
  end

  # Toggles `book.published` from the publication switch in the book sidebar.
  # GET renders the publication panel inside its turbo-frame (used by Turbo
  # to lazy-load or follow links). POST flips `book.published` based on the
  # `published` form param and responds with a turbo-stream that replaces
  # the frame's contents (or a plain redirect for non-Turbo clients).
  class BookPublicationHandler < Marten::Handler
    include ::Accounts::AuthenticationHelpers
    include MartenTurbo::Handlers::Concerns::Streamable

    @book : Book? = nil

    before_dispatch :require_authentication
    before_dispatch :load_book
    before_dispatch :ensure_editable

    def get
      render(
        "books/publications/_publication.html",
        context: {book: book, editable: true, frame_id: "book_publication_#{book.pk}"},
      )
    end

    def post
      raw = request.data["published"]?.try(&.to_s)
      # Form check_box convention: presence (anything truthy) = true; missing = false.
      new_value = !(raw.nil? || raw.empty? || raw == "0" || raw == "false")
      book.published = new_value
      book.save!

      if request.turbo?
        frame_id = "book_publication_#{book.pk}"
        turbo_frame_replace(
          frame_id,
          partial: "books/publications/_publication.html",
          locals: {book: book, editable: true, frame_id: frame_id},
        )
      else
        redirect(Marten.routes.reverse("books:show", id: book.pk!))
      end
    end

    private def book : Book
      @book.not_nil!
    end

    private def load_book : Marten::HTTP::Response?
      @book = Book.get(pk: params["id"]?)
      if @book.nil?
        return head :not_found
      end
      nil
    end

    private def ensure_editable : Marten::HTTP::Response?
      unless book.editable?(current_user)
        return head :forbidden
      end
      nil
    end
  end

  # Markdown export — concatenates every active leaf's `markable` into one
  # document with a YAML frontmatter block (mirrors Rails'
  # `app/views/books/show.md.erb`). Linked from `books/show.html` via
  # `<link rel="alternate" type="text/markdown">`.
  class BooksMarkdownHandler < Marten::Handler
    include ::Accounts::AuthenticationHelpers

    def get
      book = Book.accessable_or_published(current_user).filter(pk: params["id"]?).first
      return respond("Not found", status: 404) if book.nil?

      url = "#{request.scheme}://#{request.host}#{Marten.routes.reverse("books:show", id: book.pk!)}"
      content = String.build do |io|
        io << "---\n"
        io << "title: " << %("#{book.title.to_s.gsub('"', "\\\"")}") << '\n'
        io << "author: " << %("#{book.author.to_s.gsub('"', "\\\"")}") << '\n'
        io << "url: " << %("#{url}") << '\n'
        io << "---\n\n"
        io << book.markable
      end
      respond(content, content_type: "text/markdown", status: 200)
    end
  end

  class BooksDeleteHandler < Marten::Handlers::RecordDelete
    include ::Accounts::AuthenticationHelpers

    before_dispatch :require_authentication
    before_dispatch :ensure_editable

    model Book
    template_name "books/delete.html"
    record_context_name "book"
    success_route_name "books:index"
    lookup_param "id"

    private def ensure_editable : Marten::HTTP::Response?
      book = record
      unless book.editable?(current_user)
        return head :forbidden
      end
      nil
    end
  end
end
