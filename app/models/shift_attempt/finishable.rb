# The end of a shift: when the clock reaches the time budget, when every task is resolved, or when
# the player ends it. Finishing scores the attempt from its log.
module ShiftAttempt::Finishable
  extend ActiveSupport::Concern

  included do
    scope :finished, -> { where.not(status: :open) }
    scope :scored, -> { where(scored: true) }
  end

  def finished?
    !open?
  end

  def end_shift
    acting_on do
      record :end_shift, cost: 0
      finish :completed # does nothing if recording the action already ended the shift
    end
  end

  def scorecard
    ShiftAttempt::Scorecard.new(shift:, actions:, arrived_by: clock_minutes)
  end

  private
    def finish_if_over
      if time_up?
        finish :timed_out
      elsif all_tasks_resolved?
        finish :completed
      end
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
