# The end of a shift. It ends by itself once every message has been dealt with (the inbox is empty and
# nothing more is coming), when the player gives up, or when it's left open too long. Anything not
# dealt with by then counts as ignored. Finishing scores the attempt from its log.
module ShiftAttempt::Finishable
  extend ActiveSupport::Concern

  included do
    scope :finished, -> { where.not(status: :open) }
    scope :scored, -> { where(scored: true) }
  end

  class_methods do
    # The highest-scoring finished attempt at each of the given shifts, keyed by shift id: the
    # player's progress on a track page. Ties go to the earlier attempt.
    def best_by_shift(shifts)
      finished.where(shift: shifts)
        .select("DISTINCT ON (shift_attempts.shift_id) shift_attempts.*")
        .reorder(:shift_id, score: :desc, completed_at: :asc)
        .includes(:attempt_actions, :shift).index_by(&:shift_id)
    end
  end

  def finished?
    !open?
  end

  def give_up
    acting_on do
      record :give_up
      finish :gave_up
    end
  end

  def scorecard
    ShiftAttempt::Scorecard.new(shift:, actions:, elapsed_seconds:, cleared: completed? || (open? && inbox_messages.empty?), relaxed:)
  end

  private
    def finish_if_cleared
      finish :completed if open? && inbox_messages.empty?
    end

    def finish(status)
      return if finished?

      self.status = status
      self.completed_at = Time.current
      update! scored: first_scored_attempt?, score: scorecard.total
    end

    # XP (from M8) is only for confirmed players' first finished attempt at each shift.
    def first_scored_attempt?
      user.earns_xp? && !user.shift_attempts.scored.where.not(id:).exists?(shift_id:)
    end
end
