# A player's run through a shift. Created on the server with a random token. The player acts on it
# through the methods its concerns add: read, expand_headers, verify_sender, flag, send_reply, visit,
# open_attachment, close_tab, use_portal, submit_credentials, run_download, report, archive, use_hint
# and give_up. Each one is logged as an AttemptAction with the time it was made.
#
# The shift ends when every message has been dealt with (reported or archived), when the player gives
# up, or when it's left open too long.
#
# Everything here describes what the player can already see. Nothing answers whether a message is
# phishing, or what it needed, until the shift is over and scored.
class ShiftAttempt < ApplicationRecord
  # Raised when a move isn't allowed: the shift is over, the message has already been dealt with, and
  # so on. The message is shown to the player.
  class Rejected < StandardError; end

  include Timed, Logged, Inbox, Reading, HeaderExpandable, Verifiable, Flaggable, Replyable, Hintable,
    Browsing, Portals, Compromisable, Reportable, Archivable, Finishable

  enum :status, { open: "open", completed: "completed", gave_up: "gave_up", timed_out: "timed_out" }, validate: true

  belongs_to :user
  belongs_to :shift

  has_secure_token :token, length: 32

  before_validation -> { self.started_at ||= Time.current }, on: :create

  def self.start(user:, shift:)
    user.shift_attempts.open.find_or_create_by!(shift:) { |attempt| attempt.relaxed = user.relaxed_mode }
  rescue ActiveRecord::RecordNotUnique
    user.shift_attempts.open.find_by!(shift:)
  end

  def to_param
    token
  end
end
