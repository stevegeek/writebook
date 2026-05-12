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
    include MartenTurbo::Identifiable

    protected def broadcast_being_edited(target_leaf : Leaf) : Nil
      user = current_user
      return if user.nil?
      # Stream name (WebSocket channel) — arbitrary identifier, must match
      # the {% turbo_stream_from being_edited_stream %} in the indicator partial.
      stream = "leaf_#{target_leaf.pk!}_being_edited"
      # DOM target id — must match `{% dom_id leaf %}_being_edited` in
      # _being_edited_indicator.html (marten-turbo dom_id → `books_leaf_<pk>`).
      MartenTurbo.broadcast_append_to(
        stream,
        target: "#{dom_id(target_leaf)}_being_edited",
        partial: "leaves/_being_edited_by.turbo_stream.html",
        locals: {"leaf" => target_leaf, "user" => user},
      )
    end
  end
end
