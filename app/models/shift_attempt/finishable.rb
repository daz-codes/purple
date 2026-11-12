# The end of a shift: when the clock reaches the time budget, or when the player ends it. Clearing the
# task list doesn't end it: the rest of the day's mail arrives instead (see Inbox), and the player
# has to deal with everything. Finishing scores the attempt from its log.
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
      finished.where(shift: shifts).includes(:attempt_actions, :shift).order(score: :desc, completed_at: :asc)
        .group_by(&:shift_id).transform_values(&:first)
    end
  end

  def finished?
    !open?
  end

  def end_shift
    acting_on do
      record :end_shift, cost: 0
      finish :completed # does nothing if recording the action already ran the clock out
    end
  end

  def scorecard
    ShiftAttempt::Scorecard.new(shift:, actions:, arrived_by: clock_minutes)
  end

  private
    def finish_if_over
      finish :timed_out if time_up?
    end

    def finish(status)
      return if finished?

      card = scorecard
      update! status:, completed_at: Time.current, scored: first_scored_attempt?,
        productivity_score: card.productivity, security_score: card.security, score: card.total
    end

    # XP (from M8) is only for confirmed players' first finished attempt at each shift.
    def first_scored_attempt?
      user.earns_xp? && !user.shift_attempts.scored.where.not(id:).exists?(shift_id:)
    end
end
