module Books
  # Edit-history handlers. Each handler is scoped to a single leaf (by
  # `leaf_id` route param) and lists/shows the leaf's revision snapshots.
  #
  # Rails has a single `Pages::EditsController#show` that resolves
  # `params[:id]` to either an Edit row or the special string `"latest"`
  # and renders the revision plus a prev/next nav. We add an explicit
  # index handler to power the popover/dialog list on the edit toolbar
  # (Rails renders that inline from `leaves/_history.html.erb` because
  # the popover is just a single button linking to `latest`; we host a
  # turbo-frame list so the popover can show all revisions at once).

  # GET /leaves/<leaf_id>/edits
  #
  # Returns a fragment listing every revision for the leaf, ordered most-
  # recent first. Rendered into a turbo-frame opened by the history
  # button on the edit toolbar (`leaves/_history.html`).
  class EditsIndexHandler < Marten::Handler
    include ::Accounts::AuthenticationHelpers

    before_dispatch :require_authentication

    def get
      target_leaf = leaf
      return respond("Not found", status: 404) if target_leaf.nil?

      target_book = target_leaf.book!
      return head :forbidden unless target_book.editable?(current_user)

      edits = target_leaf.edits.order("-created_at").to_a

      render("leaves/edits/index.html", context: {
        leaf:  target_leaf,
        book:  target_book,
        edits: edits,
      })
    end

    private def leaf : Leaf?
      Leaf.get(pk: params["leaf_id"]?)
    end
  end

  # GET /leaves/<leaf_id>/edits/<id>
  #
  # Renders a single revision of the leaf — the leafable content as it
  # was at the moment the edit was recorded — alongside the current
  # version. `id` may be the integer pk of an `Edit` row, or the special
  # string `"latest"`.
  class EditsShowHandler < Marten::Handler
    include ::Accounts::AuthenticationHelpers

    before_dispatch :require_authentication

    def get
      target_leaf = leaf
      return respond("Not found", status: 404) if target_leaf.nil?

      target_book = target_leaf.book!
      return head :forbidden unless target_book.editable?(current_user)

      edit = resolve_edit(target_leaf)
      return respond("Revision not found", status: 404) if edit.nil?

      # Render the historical leafable's content. For Pages, the snapshot
      # is a separate `Leafables::Page` row pointed at by the Edit; we
      # render its markdown body. Sections store their body inline.
      # Pictures store only the caption.
      historical_html = render_leafable_html(edit.leafable)
      current_html = render_leafable_html(target_leaf.leafable)

      render("leaves/edits/show.html", context: {
        leaf:            target_leaf,
        book:            target_book,
        edit:            edit,
        previous_edit:   edit.previous_edit,
        next_edit:       edit.next_edit,
        historical_html: historical_html,
        current_html:    current_html,
        edit_url:        Marten.routes.reverse("pages:edit", id: target_leaf.pk!),
      })
    end

    private def resolve_edit(target_leaf : Leaf) : Edit?
      raw = params["id"]?
      # The two named routes that point at this handler:
      #   - `edits:show`        — `<id:int>` (raw is Int64)
      #   - `edits:show_latest` — no `<id>` capture, raw is nil
      if raw.nil?
        target_leaf.edits.order("-created_at").first
      else
        target_leaf.edits.filter(id: raw.to_s.to_i64?).first
      end
    end

    private def render_leafable_html(leafable) : String
      case leafable
      when Leafables::Page
        leafable.body.try(&.to_html) || ""
      when Leafables::Section
        leafable.body_html
      when Leafables::Picture
        # Pictures don't have a body to diff; show the caption.
        "<figcaption>#{HTML.escape(leafable.caption.to_s)}</figcaption>"
      else
        ""
      end
    end

    private def leaf : Leaf?
      Leaf.get(pk: params["leaf_id"]?)
    end
  end
end
