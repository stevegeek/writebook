module Books
  # POST /books/<book_id>/leaves/<id>/delete — soft-delete a leaf.
  # Calls leaf.trashed! (sets status: "trashed") and redirects to the book.
  class LeavesDestroyHandler < Marten::Handler
    include ::Accounts::AuthenticationHelpers

    before_dispatch :require_authentication

    def post
      target_leaf = leaf
      return head :not_found if target_leaf.nil?

      target_book = target_leaf.book
      return head :not_found if target_book.nil?

      unless target_book.editable?(current_user)
        return head :forbidden
      end

      target_leaf.trashed!

      redirect(Marten.routes.reverse("books:show", id: target_book.pk))
    end

    # Only POST is allowed; everything else → 405
    def get
      head :method_not_allowed
    end

    private def leaf : Leaf?
      Leaf.get(pk: params["id"]?, book_id: params["book_id"]?)
    end
  end

  # POST /books/<book_id>/leaves/moves — reorder leaves via drag-and-drop.
  # Accepts:
  #   position  — target 0-based index (Int)
  #   id[]      — one or more leaf IDs; the first is the primary leaf,
  #               the rest are "followed_by" companions.
  # Returns 204 No Content on success.
  # The arrangement_controller.js (Stimulus) posts via @rails/request.js
  # which adds X-CSRF-Token from the meta tag. Marten checks the csrftoken
  # cookie (double-submit pattern) so the CSRF middleware is satisfied.
  class LeavesMovesHandler < Marten::Handler
    include ::Accounts::AuthenticationHelpers

    before_dispatch :require_authentication

    def post
      target_book = book
      return head :not_found if target_book.nil?

      unless target_book.editable?(current_user)
        return head :forbidden
      end

      # Parse id[] — multi-value param submitted as repeated keys
      raw_ids = request.data.fetch_all("id[]", nil)
      return head :unprocessable_entity if raw_ids.nil?

      position_str = request.data["position"]?.try(&.to_s) || "0"
      position = position_str.to_i? || 0

      leaf_ids = raw_ids.compact_map { |v| v.to_s.to_i64? }
      return head :unprocessable_entity if leaf_ids.empty?

      leaves = leaf_ids.compact_map { |id| Leaf.get(pk: id, book_id: target_book.pk) }

      primary = leaves.first?
      return head :not_found if primary.nil?

      followed = leaves.size > 1 ? leaves[1..] : [] of Leaf

      primary.move_to_position(position, followed_by: followed)

      head :no_content
    end

    def get
      head :method_not_allowed
    end

    private def book : Book?
      Book.get(pk: params["book_id"]?)
    end
  end
end
