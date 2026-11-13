# The append-only log of everything the player did. It drives arrivals and the scoring, and it's
# replayed in the Purple debrief.
#
# Every move goes through #acting_on, which locks the attempt (so two tabs can't race each other) and
# checks the shift is still open, then #record, which logs the move with the time it was made, adds
# any penalty, and ends the shift once the inbox is clear.
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
        reject "This shift is over." unless open? && !stale?
        if message
          reject "That message isn't in your inbox." unless arrived_messages.include?(message)
          reject "You've already dealt with that message." if handled?(message)
        end

        yield
      end
    end

    def record(kind, message: nil, target_key: message&.key, penalty: 0, result: {})
      action = attempt_actions.create!(kind:, target_key:, at_seconds: elapsed_seconds, penalty_seconds: penalty, result:)
      increment!(:penalty_seconds, penalty) if penalty.positive?
      reload
      finish_if_cleared

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
