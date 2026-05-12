module Books
  # Edit-history concern for Leaf. New revisions only created when the
  # leafable's content actually changed AND the previous edit is older than
  # MINIMUM_TIME_BETWEEN_VERSIONS — otherwise the previous revision is
  # `touch`ed in place. Trash events also recorded.
  module Editable
    MINIMUM_TIME_BETWEEN_VERSIONS = 10.minutes

    macro included
      after_update :record_moved_to_trash_if_needed
    end

    private def record_moved_to_trash_if_needed : Nil
      record_moved_to_trash if was_trashed?
    end

    def edit(leafable_params : Hash(String, String), leaf_params : Hash(String, String)) : Nil
      if record_new_edit?(leafable_params)
        update_and_record_edit(leaf_params, leafable_params)
      else
        update_without_recording_edit(leaf_params, leafable_params)
      end
    end

    private def record_new_edit?(leafable_params : Hash(String, String)) : Bool
      will_change_leafable?(leafable_params) && last_edit_old?
    end

    private def last_edit_old? : Bool
      last = edits.order(:created_at).last
      last.nil? || last.created_at! < MINIMUM_TIME_BETWEEN_VERSIONS.ago
    end

    private def will_change_leafable?(leafable_params : Hash(String, String)) : Bool
      # Conservative: any non-empty params hash counts as a change. The
      # handler is the right place to do exact diffing once we have a way
      # to inspect the leafable's current values uniformly across types.
      !leafable_params.empty?
    end

    private def update_without_recording_edit(leaf_params, leafable_params) : Nil
      Marten::DB::Connection.default.transaction do
        apply_leafable_params(leafable_params)
        latest = edits.order(:created_at).last
        latest.update!(updated_at: Time.local) if latest
        update!(leaf_params)
      end
    end

    private def update_and_record_edit(leaf_params, leafable_params) : Nil
      Marten::DB::Connection.default.transaction do
        original = leafable!
        new_leafable = dup_leafable_with_attachments(original)
        apply_leafable_params_to(new_leafable, leafable_params)
        new_leafable.save!
        Edit.create!(leaf: self, leafable: original, event: "revision")
        update!(leaf_params.merge({"leafable_type" => new_leafable.class.name, "leafable_id" => new_leafable.pk.to_s}))
      end
    end

    private def apply_leafable_params(leafable_params : Hash(String, String)) : Nil
      target = leafable
      apply_leafable_params_to(target, leafable_params) if target
    end

    private def apply_leafable_params_to(target, leafable_params : Hash(String, String)) : Nil
      leafable_params.each do |key, value|
        if key == "body" && target.is_a?(Leafables::Page)
          target.body = value
        elsif key == "body" && target.is_a?(Leafables::Section)
          target.body = value
        elsif key == "caption" && target.is_a?(Leafables::Picture)
          target.caption = value
        end
      end
      target.save! if target.responds_to?(:save!)
    end

    private def dup_leafable_with_attachments(original)
      case original
      when Leafables::Page
        Leafables::Page.new
      when Leafables::Section
        Leafables::Section.new(body: original.body)
      when Leafables::Picture
        Leafables::Picture.new(caption: original.caption)
      else
        raise "Unknown leafable type: #{original.class}"
      end
    end

    private def record_moved_to_trash : Nil
      target = leafable
      Edit.create!(leaf: self, leafable: target, event: "trash") if target
    end

    private def was_trashed? : Bool
      status == "trashed"
    end
  end
end
