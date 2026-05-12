module Books
  # Pictures — image-bearing leaves of a Book. New picture flow:
  #   1. Create empty Leafables::Picture row (so it has a pk).
  #   2. Attach the uploaded image via MartenStorages::Service.attach (saves
  #      an Attachment row + pre-computes the "large" variant via vips).
  #   3. Create a Leaf wrapping the picture, attached to the book, in a
  #      transaction.
  class PicturesNewHandler < Marten::Handlers::Schema
    include ::Accounts::AuthenticationHelpers

    before_dispatch :require_authentication

    schema PictureSchema
    template_name "pictures/new.html"

    def context
      super.merge({"book" => book})
    end

    def process_valid_schema
      target_book = book
      return respond("Book not found", status: 404) if target_book.nil?

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
        Leaf.create!(book: target_book, leafable: pic, title: leaf_title, status: "active")
      end

      redirect(Marten.routes.reverse("books:show", id: target_book.pk))
    end

    private def book : Book?
      Book.get(pk: params["book_id"]?)
    end
  end

  # Markdown export for a single picture leaf. Pictures aren't really
  # markdown; Rails serves only the caption (`Picture#markable` returns the
  # caption string). Mirrors `app/views/leafables/show.md.erb`.
  class PicturesMarkdownHandler < Marten::Handler
    include ::Accounts::AuthenticationHelpers
    include ::Accounts::UrlHelpers

    def get
      leaf = Leaf.get(pk: params["id"]?)
      return respond("Not found", status: 404) if leaf.nil?

      picture = leaf.leafable.try(&.as?(Leafables::Picture))
      return respond("Not a picture", status: 404) if picture.nil?

      book = leaf.book!
      unless book.published || book.accessable?(current_user) || book.editable?(current_user)
        return respond("Not found", status: 404)
      end

      url = absolute_url("pictures:show", id: leaf.pk!)
      content = String.build do |io|
        io << "---\n"
        io << "title: " << %("#{leaf.title.to_s.gsub('"', "\\\"")}") << '\n'
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

    before_dispatch :require_authentication

    def post
      target_book = book
      return head :not_found if target_book.nil?
      return head :forbidden unless target_book.editable?(current_user)

      created_leaf = nil
      Marten::DB::Connection.default.transaction do
        picture = Leafables::Picture.create!
        created_leaf = Leaf.create!(book: target_book, leafable: picture, title: "New picture", status: "active")
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

  class PicturesShowHandler < Marten::Handler
    include ::Accounts::AuthenticationHelpers

    def get
      leaf = Leaf.get(pk: params["id"]?)
      return respond("Not found", status: 404) if leaf.nil?

      picture = leaf.leafable.try(&.as?(Leafables::Picture))
      return respond("Not a picture", status: 404) if picture.nil?

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

      attachment = MartenStorages::Service.find_one(model: Attachment, record: picture, name: "image")
      edit_url = Marten.routes.reverse("pictures:edit", id: leaf.pk!)
      render("pictures/show.html", context: {
        leaf:          leaf,
        picture:       picture,
        book:          book,
        leaves:        leaves,
        previous_leaf: prev_leaf,
        next_leaf:     next_leaf,
        attachment:    attachment,
        signed_in:     signed_in?,
        editable:      book.editable?(current_user),
        edit_url:      edit_url,
      })
    end
  end

  class PicturesEditHandler < Marten::Handlers::Schema
    include ::Accounts::AuthenticationHelpers
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
      book = target_leaf.book!
      active = book.leaves.filter(status: "active")
      context[:book] = book
      context[:leaves] = active.order(:position_score, :id).to_a
      context[:editable] = book.editable?(current_user)
      context[:edit_url] = Marten.routes.reverse("pictures:edit", id: target_leaf.pk!)
      context[:show_url] = Marten.routes.reverse("pictures:show", id: target_leaf.pk!)
      context[:being_edited_stream] = "leaf_#{target_leaf.pk!}_being_edited"
      context[:edits_count] = target_leaf.edits.count
      context[:previous_leaf] = active.filter(position_score__lt: target_leaf.position_score!).order("-position_score").first
      context[:next_leaf] = active.filter(position_score__gt: target_leaf.position_score!).order(:position_score).first
    end

    private def leaf : Leaf?
      Leaf.get(pk: params["id"]?)
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
