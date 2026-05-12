module Books
  # Fractional position-score ordering. Inserts have to find a `position_score`
  # between two existing rows; reorders compute mid-points; periodic rebalancing
  # is triggered when the gap between two scores gets too small.
  #
  # The host model must declare a `position_score : Float64` column.
  module Positionable
    REBALANCE_THRESHOLD = 1e-10
    ELEMENT_GAP         =  1.0

    macro included
      before_create :insert_at_default_position

      def self.positioned
        order(:position_score, :id)
      end

      def self.before(other)
        positioned.filter(position_score__lt: other.position_score!)
      end

      def self.after(other)
        positioned.filter(position_score__gt: other.position_score!)
      end

      private def insert_at_default_position : Nil
        if position_score.nil? || position_score == 0.0
          last = self.class.positioned.last
          self.position_score = last ? last.position_score!.to_f64 + ELEMENT_GAP : 0.0
        end
      end
    end

    def previous
      other_positioned_siblings
        .filter(position_score__lt: position_score!)
        .order(:position_score, :id)
        .last
    end

    def next_sibling
      other_positioned_siblings
        .filter(position_score__gt: position_score!)
        .order(:position_score, :id)
        .first
    end

    def move_to_position(offset : Int32, followed_by : Array(self) = [] of self) : Nil
      Marten::DB::Connection.default.transaction do
        all_to_move = [self] + followed_by
        siblings = other_positioned_siblings.to_a
        offset = 0 if offset < 0
        offset = siblings.size if offset > siblings.size

        before = offset == 0 ? 0.0 : siblings[offset - 1].position_score!.to_f64
        after = offset >= siblings.size ? before + ELEMENT_GAP * (all_to_move.size + 1) : siblings[offset].position_score!.to_f64
        gap = (after - before) / (all_to_move.size + 1)

        all_to_move.each_with_index do |item, index|
          item.update!(position_score: before + (index + 1) * gap)
        end

        rebalance_positions if gap < REBALANCE_THRESHOLD
      end
    end

    # No-op default. Override on the host if needed.
    def all_positioned_siblings
      self.class.positioned
    end

    def other_positioned_siblings
      all_positioned_siblings.exclude(pk: pk)
    end

    private def rebalance_positions : Nil
      siblings = all_positioned_siblings.to_a
      siblings.each_with_index do |sib, idx|
        sib.update!(position_score: (idx + 1).to_f64 * ELEMENT_GAP)
      end
    end
  end
end
