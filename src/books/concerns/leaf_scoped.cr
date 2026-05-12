module Books
  # Handler concern: resolves the requested Leaf by `params["id"]` and the
  # surrounding navigation context — book, active siblings, previous/next.
  # Mirrors the Rails `LeafablesController` superclass + `SetBookLeaf`
  # concern, which page/section/picture controllers inherited from in Rails
  # Writebook. The Marten port can't share via inheritance (each handler
  # already inherits from a generic-handler class like `Marten::Handlers::Schema`),
  # so the shared lookup-and-nav lives here as a mixin.
  #
  # Requires `Accounts::AuthenticationHelpers` for `current_user`. Wire in:
  #
  #   class PagesShowHandler < Marten::Handler
  #     include ::Accounts::AuthenticationHelpers
  #     include Books::LeafScoped
  #     before_dispatch :require_leaf
  #     before_dispatch :ensure_editable    # optional, only for edit-mode
  #   end
  #
  # `leaf` looks up by the route's `id` param — i.e. the leaf-show / leaf-edit
  # routes mounted under `/pages/<id>` / `/sections/<id>` / `/pictures/<id>`.
  # Handlers nested under `/<book_id>/...` should keep using `Books::BookScoped`.
  module LeafScoped
    @leaf : Leaf?
    @active_leaves : Marten::DB::Query::Set(Leaf)?

    # Override on the host class when the route param holding the leaf id
    # isn't named "id" — e.g. the edit-history routes mount under
    # `/<leaf_id:int>/edits/...` so `EditsShowHandler` returns "leaf_id".
    protected def leaf_param_name : String
      "id"
    end

    protected def leaf : Leaf?
      @leaf ||= Leaf.get(pk: params[leaf_param_name]?)
    end

    protected def leaf! : Leaf
      leaf.not_nil!
    end

    protected def require_leaf : Marten::HTTP::Response?
      return nil if leaf
      respond("Not found", status: 404)
    end

    # The book that owns the leaf. Delegated via the leaf's `book!` association.
    protected def book : Book?
      leaf.try(&.book!)
    end

    protected def book! : Book
      book.not_nil!
    end

    # Active sibling leaves of the current leaf's book. Unordered — consumers
    # add their own order (e.g. `active_leaves.order(:position_score, :id)`).
    # Memoised so prev/next + the full-list injection share one query plan.
    protected def active_leaves : Marten::DB::Query::Set(Leaf)
      @active_leaves ||= book!.leaves.filter(status: "active")
    end

    # The nearest active sibling with a lower position_score. Used by the
    # prev/next leaf footer nav on show / edit templates.
    protected def previous_leaf : Leaf?
      current = leaf
      return nil if current.nil?
      active_leaves.filter(position_score__lt: current.position_score!)
        .order("-position_score").first
    end

    # The nearest active sibling with a higher position_score.
    protected def next_leaf : Leaf?
      current = leaf
      return nil if current.nil?
      active_leaves.filter(position_score__gt: current.position_score!)
        .order(:position_score).first
    end

    # `before_dispatch` callback returning 403 unless the book is editable
    # by `current_user`. Mirrors Rails `LeafablesController#ensure_editable`.
    protected def ensure_editable : Marten::HTTP::Response?
      return nil if book.try(&.editable?(current_user))
      respond("Forbidden", status: 403)
    end
  end
end
