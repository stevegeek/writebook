module Books
  # Real-time "user X is editing" broadcast for leaf edits. Mirrors Rails'
  # `LeafablesController#broadcast_being_edited_indicator`. Sends the
  # `_being_edited_by` partial to the per-leaf Turbo stream that all other
  # viewers of this leaf are subscribed to via the indicator partial.
  #
  # Used by the *EditHandler classes (Pages, Pictures, Sections) — call
  # `broadcast_being_edited(target_leaf)` after a successful update.
  #
  # No-ops if there's no signed-in user (so the helper is safe to call
  # unconditionally from handlers that already guard on authentication).
  module LeafEditingBroadcast
    protected def broadcast_being_edited(target_leaf : Leaf) : Nil
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
  end
end
