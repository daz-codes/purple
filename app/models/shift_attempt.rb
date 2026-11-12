# A player's run through a shift. Created on the server with a random token. The player acts on it
# through the methods its concerns add (read, expand_headers, verify_sender, report, wait_for_mail,
# end_shift); each one is logged as an AttemptAction and moves the clock on.
#
# Everything here describes what the player can already see. Nothing answers whether a message is
# phishing until the shift is over and scored.
class ShiftAttempt < ApplicationRecord
  # Raised when a move isn't allowed: the shift is over, it doesn't fit in the time left, and so on.
  # The message is shown to the player.
  class Rejected < StandardError; end

  include Clocked, Logged, Inbox, Tasks, Reading, HeaderExpandable, Verifiable, Reportable, Finishable

  enum :status, { open: "open", completed: "completed", timed_out: "timed_out" }, validate: true

  belongs_to :user
  belongs_to :shift

  has_secure_token :token, length: 32

  before_validation -> { self.started_at ||= Time.current }, on: :create

  def self.start(user:, shift:)
    user.shift_attempts.open.find_or_create_by!(shift:)
  rescue ActiveRecord::RecordNotUnique
    user.shift_attempts.open.find_by!(shift:)
  end

  def to_param
    token
  end
end
