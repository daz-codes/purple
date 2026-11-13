# Time in a shift is real time, measured only on the server from when the attempt started, plus any
# penalties: calling the sender back (or checking with someone you trust) adds 30 seconds. No clock is
# shown to the player; time only counts in the debrief, as a speed bonus against the shift's target.
#
# Relaxed mode (copied from the player's setting when the attempt starts) turns timing off: no speed
# bonus and no urgency penalties. An attempt left open for two hours expires.
module ShiftAttempt::Timed
  extend ActiveSupport::Concern

  CALL_PENALTY = 30
  EXPIRES_AFTER = 2.hours

  included do
    validates :penalty_seconds, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  end

  # Seconds since the shift started, plus penalties, up to when it finished.
  def elapsed_seconds(now: Time.current)
    ((completed_at || now) - started_at).to_i + penalty_seconds
  end

  def stale?(now: Time.current)
    open? && now - started_at > EXPIRES_AFTER
  end

  # Closes an attempt left open too long. Anything still in the inbox counts as ignored.
  def expire_if_stale
    with_lock { finish :timed_out if stale? }
  end
end
