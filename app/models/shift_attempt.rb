# A player's run through a shift. Created on the server with a random token. The player acts on it
# through the methods its concerns add: read, expand_headers, verify_sender, flag, save_note, send_reply
# (including asking why), share_details, visit, open_attachment, close_tab, use_portal,
# submit_credentials, run_download, report, archive, use_hint and clock_off. Each one is logged as an AttemptAction with the time it was made.
#
# The shift ends when every message has been dealt with (reported or archived), when the player clocks
# off early, or when it's left open too long.
#
# Each attempt has its own persona (ShiftAttempt::Identified): the private details the player works with.
#
# Everything here describes what the player can already see. Nothing answers whether a message is
# phishing, or what it needed, until the shift is over and scored.
class ShiftAttempt < ApplicationRecord
  # Raised when a move isn't allowed: the shift is over, the message has already been dealt with, and
  # so on. The message is shown to the player.
  class Rejected < StandardError; end

  include Timed, Logged, Identified, Inbox, Reading, HeaderExpandable, Verifiable, Flaggable, Notable, Replyable,
    Sharing, Hintable, Browsing, Portals, Compromisable, Reportable, Archivable, Finishable

  enum :status, { open: "open", completed: "completed", clocked_off: "clocked_off", timed_out: "timed_out" }, validate: true

  belongs_to :user
  belongs_to :shift

  has_secure_token :token, length: 32

  before_validation -> { self.started_at ||= Time.current }, on: :create

  # Starts a shift, or resumes the one in progress. An attempt left idle too long is closed first, so the
  # player gets a fresh shift rather than a debrief for one they walked away from.
  def self.start(user:, shift:)
    user.shift_attempts.open.where(shift:).each(&:expire_if_stale)
    user.shift_attempts.open.find_or_create_by!(shift:) { |attempt| attempt.relaxed = user.relaxed_mode }
  rescue ActiveRecord::RecordNotUnique
    user.shift_attempts.open.find_by!(shift:)
  end

  def to_param
    token
  end

  # --- Progress (see Rewarded) ---------------------------------------------------------

  include Rewarded

  def side = "blue"
  def xp_reason = :shift_completed
  def finished_at = completed_at

  # Finished just now by playing it: an attempt that expired doesn't count as a day played.
  def just_finished?
    saved_change_to_status? && (completed? || clocked_off?)
  end
end
