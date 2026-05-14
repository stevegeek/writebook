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
    @sorted_active_leaves : Array(Leaf)?

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
    # add their own order. Kept as a queryset for callers that want to add
    # filters (the search handler does this); most callers want
    # `sorted_active_leaves` instead.
    protected def active_leaves : Marten::DB::Query::Set(Leaf)
      @active_leaves ||= book!.leaves.filter(status: "active")
    end

    # The book's active leaves loaded once, sorted by position, with the
    # polymorphic `leafable` prefetched in a single batched query per type.
    # Memoised so the show/edit handlers' context injection and the prev/next
    # nav share one SELECT (+ one prefetch) instead of three independent ones.
    protected def sorted_active_leaves : Array(Leaf)
      @sorted_active_leaves ||= active_leaves
        .prefetch(:leafable)
        .order(:position_score, :id)
        .to_a
    end

    # The previous active sibling, derived from `sorted_active_leaves` to
    # avoid an extra SELECT (+ lazy leafable lookup at template render time).
    protected def previous_leaf : Leaf?
      neighbour(-1)
    end

    # The next active sibling, derived from `sorted_active_leaves`.
    protected def next_leaf : Leaf?
      neighbour(+1)
    end

    private def neighbour(offset : Int32) : Leaf?
      current = leaf
      return nil if current.nil?
      list = sorted_active_leaves
      idx = list.index { |l| l.pk == current.pk }
      return nil if idx.nil?
      target = idx + offset
      return nil if target < 0 || target >= list.size
      list[target]
    end

    # `before_dispatch` callback returning 403 unless the book is editable
    # by `current_user`. Mirrors Rails `LeafablesController#ensure_editable`.
    protected def ensure_editable : Marten::HTTP::Response?
      return nil if book.try(&.editable?(current_user))
      respond("Forbidden", status: 403)
    end
  end
end
