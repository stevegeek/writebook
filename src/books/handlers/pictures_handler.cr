module Books
  # Pictures — image-bearing leaves of a Book. New picture flow:
  #   1. Create empty Leafables::Picture row (so it has a pk).
  #   2. Attach the uploaded image via MartenStorages::Service.attach (saves
  #      an Attachment row + pre-computes the "large" variant via vips).
  #   3. Create a Leaf wrapping the picture, attached to the book, in a
  #      transaction.
  class PicturesNewHandler < Marten::Handlers::Schema
    include ::Accounts::AuthenticationHelpers
    include BookScoped

    before_dispatch :require_authentication
    before_dispatch :require_book
    before_dispatch :ensure_editable

    schema PictureSchema
    template_name "pictures/new.html"

    def context
      super.merge({"book" => book!})
    end

    def process_valid_schema
      target_book = book!
      caption = (schema.validated_data["caption"]?.as(String?) || "").strip
      title = (schema.validated_data["title"]?.as(String?) || "").strip
      uploaded = schema.validated_data["image"]?.as(Marten::HTTP::UploadedFile?)

      Marten::DB::Connection.default.transaction do
        pic = Leafables::Picture.create!(caption: caption.presence)
        if uploaded
          MartenStorages::Service.attach(
            model: Attachment,
            record: pic,
            name: "image",
            uploaded_file: uploaded,
            variants: {"large" => {max_dimension: 1500}},
          )
        end
        leaf_title = title.presence || caption.presence || "Picture"
        target_book.press(pic, title: leaf_title)
      end

      redirect(Marten.routes.reverse("books:show", id: target_book.pk))
    end
  end

  # Markdown export for a single picture leaf. Pictures aren't really
  # markdown; Rails serves only the caption (`Picture#markable` returns the
  # caption string). Mirrors `app/views/leafables/show.md.erb`.
  class PicturesMarkdownHandler < Marten::Handler
    include ::Accounts::AuthenticationHelpers
    include ::Accounts::UrlHelpers
    include LeafScoped

    before_dispatch :require_leaf

    def get
      target_leaf = leaf!
      picture = target_leaf.leafable.try(&.as?(Leafables::Picture))
      return respond("Not a picture", status: 404) if picture.nil?

      target_book = book!
      unless target_book.published || target_book.accessable?(current_user) || target_book.editable?(current_user)
        return respond("Not found", status: 404)
      end

      url = absolute_url("pictures:show", id: target_leaf.pk!)
      content = String.build do |io|
        io << "---\n"
        io << "title: " << %("#{target_leaf.title.to_s.gsub('"', "\\\"")}") << '\n'
        io << "url: " << %("#{url}") << '\n'
        io << "---\n\n"
        io << picture.markable
      end
      respond(content, content_type: "text/markdown", status: 200)
    end
  end

  # Inline-create endpoint. POSTed by the "+ Picture" button in the TOC toolbar.
  # Note: the picture itself has no image yet; user uploads via the edit form.
  class PicturesCreateHandler < Marten::Handler
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
        picture = Leafables::Picture.create!
        created_leaf = target_book.press(picture, title: "New picture")
      end

      leaf = created_leaf.not_nil!

      if request.turbo?
        turbo_stream("books/leafable_create.turbo_stream.html", {"leaf" => leaf})
      else
        redirect(Marten.routes.reverse("books:show", id: target_book.pk))
      end
    end
  end

  class PicturesShowHandler < Marten::Handler
    include ::Accounts::AuthenticationHelpers
    include LeafScoped

    before_dispatch :require_leaf

    def get
      target_leaf = leaf!
      picture = target_leaf.leafable.try(&.as?(Leafables::Picture))
      return respond("Not a picture", status: 404) if picture.nil?

      target_book = book!

      request.cookies.set(
        "reading_progress_#{target_book.pk}",
        target_leaf.id.to_s,
        expires: 1.year.from_now,
        path: "/"
      )

      attachment = MartenStorages::Service.find_one(model: Attachment, record: picture, name: "image")
      render("pictures/show.html", context: {
        leaf:          target_leaf,
        picture:       picture,
        book:          target_book,
        leaves:        active_leaves.prefetch(:leafable).order(:position_score, :id).to_a,
        previous_leaf: previous_leaf,
        next_leaf:     next_leaf,
        attachment:    attachment,
        signed_in:     signed_in?,
        editable:      target_book.editable?(current_user),
        edit_url:      Marten.routes.reverse("pictures:edit", id: target_leaf.pk!),
      })
    end
  end

  class PicturesEditHandler < Marten::Handlers::Schema
    include ::Accounts::AuthenticationHelpers
    include LeafScoped
    include LeafEditingBroadcast

    before_dispatch :require_authentication
    before_render :inject_book_context

    schema PictureSchema
    template_name "pictures/edit.html"

    def context
      super.merge({"leaf" => leaf, "picture" => picture, "attachment" => current_attachment})
    end

    def initial_data
      target_leaf = leaf
      target_picture = picture
      if target_leaf && target_picture
        {
          "title"   => target_leaf.title.to_s,
          "caption" => target_picture.caption.to_s,
        }
      else
        super
      end
    end

    def process_valid_schema
      target_leaf = leaf
      target_picture = picture
      return respond("Not found", status: 404) if target_leaf.nil? || target_picture.nil?

      caption = (schema.validated_data["caption"]?.as(String?) || "").strip
      title = (schema.validated_data["title"]?.as(String?) || "").strip
      uploaded = schema.validated_data["image"]?.as(Marten::HTTP::UploadedFile?)

      Marten::DB::Connection.default.transaction do
        target_picture.update!(caption: caption.presence)
        if uploaded
          MartenStorages::Service.attach(
            model: Attachment,
            record: target_picture,
            name: "image",
            uploaded_file: uploaded,
            variants: {"large" => {max_dimension: 1500}},
          )
        end
        new_title = title.presence || caption.presence || target_leaf.title.presence || "Picture"
        target_leaf.update!(title: new_title)
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
      context[:leaves] = active_leaves.prefetch(:leafable).order(:position_score, :id).to_a
      context[:editable] = book!.editable?(current_user)
      context[:edit_url] = Marten.routes.reverse("pictures:edit", id: target_leaf.pk!)
      context[:show_url] = Marten.routes.reverse("pictures:show", id: target_leaf.pk!)
      context[:being_edited_stream] = "leaf_#{target_leaf.pk!}_being_edited"
      context[:edits_count] = target_leaf.edits.count
      context[:previous_leaf] = previous_leaf
      context[:next_leaf] = next_leaf
    end

    private def picture : Leafables::Picture?
      leaf.try(&.leafable.try(&.as?(Leafables::Picture)))
    end

    private def current_attachment : Attachment?
      pic = picture
      pic ? MartenStorages::Service.find_one(model: Attachment, record: pic, name: "image") : nil
    end
  end
end
