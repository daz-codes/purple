# The append-only log of everything the player did. It drives the clock and the scoring, and from
# M5 it's replayed in the Purple debrief.
#
# Every move goes through #acting_on, which locks the attempt (so two tabs can't race the clock)
# and checks the shift is still open, then #record, which logs the move, charges its minutes and
# ends the shift if that was the last of the day.
module ShiftAttempt::Logged
  extend ActiveSupport::Concern

  included do
    has_many :attempt_actions, -> { order(:id) }, dependent: :delete_all, inverse_of: :shift_attempt
  end

  def actions
    @actions ||= attempt_actions.to_a
  end

  def reload(*)
    reset_log_memos
    super
  end

  private
    def acting_on(message = nil)
      with_lock do
        reject "This shift is over." unless open?
        if message
          reject "That message isn't in your inbox." unless arrived_messages.include?(message)
          reject "You've already reported that message." if reported?(message)
        end

        yield
      end
    end

    # target_key is the message's key, or for a completed task the task's key.
    def record(kind, message: nil, target_key: message&.key, cost: action_cost(kind), result: {})
      unless affordable?(cost)
        reject "Not enough time left: that takes #{cost} min and you have #{minutes_left}."
      end

      action = attempt_actions.create!(kind:, target_key:, minute: clock_minutes, cost_minutes: cost, result:)
      advance_clock(cost)
      reload
      finish_if_over

      action
    end

    def done?(kind, target_key)
      @done ||= actions.to_set { |action| [ action.kind, action.target_key ] }
      @done.include?([ kind.to_s, target_key ])
    end

    def reject(message)
      raise ShiftAttempt::Rejected, message
    end

    def reset_log_memos
      @actions = @done = nil
    end
end
