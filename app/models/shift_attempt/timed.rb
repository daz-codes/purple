# Time in a shift is real time, measured only on the server from when the attempt started, plus any
# penalties: calling the sender back (or checking with someone you trust) adds 30 seconds. No clock is
# shown to the player; time only counts in the debrief, as a speed bonus against the shift's target.
#
# Relaxed mode (copied from the player's setting when the attempt starts) turns timing off: no speed
# bonus and no urgency penalties. An attempt left idle for two hours (no move made) expires, in relaxed
# mode too: taking as long as you like means as long as you keep playing.
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
    open? && now - last_active_at > EXPIRES_AFTER
  end

  # When the player last made a move, or started the shift.
  def last_active_at
    actions.last&.created_at || started_at
  end

  # Closes an attempt left idle too long. Anything still in the inbox counts as ignored. Only takes the
  # lock when it looks stale, and checks again once it has it.
  def expire_if_stale
    return unless stale?

    with_lock { finish :timed_out if stale? }
  end
end
