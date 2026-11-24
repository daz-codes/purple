# A player's run through a mission. Created on the server with a random token. The player acts on it
# through the methods its concerns add: read, expand_headers, verify_sender, flag, save_note, send_reply
# (including asking why), share_details, visit, open_attachment, close_tab, use_portal,
# submit_credentials, run_download, report, archive, use_hint and stand_down; in a signals mission,
# submit_flag (MissionAttempt::Decoding). Each one is logged as an AttemptAction with the time it was made.
#
# The mission ends when it's cleared (every message dealt with, or every intercept solved or closed),
# when the player stands down early, or when it's left open too long.
#
# Each attempt has its own persona (MissionAttempt::Identified): the private details the player works with.
#
# Everything here describes what the player can already see. Nothing answers whether a message is
# phishing, or what it needed, until the mission is over and scored.
class MissionAttempt < ApplicationRecord
  # Raised when a move isn't allowed: the mission is over, the message has already been dealt with, and
  # so on. The message is shown to the player.
  class Rejected < StandardError; end

  include Timed, Logged, Identified, Inbox, Reading, HeaderExpandable, Verifiable, Flaggable, Notable, Replyable,
    Sharing, Hintable, Browsing, Portals, Compromisable, Reportable, Archivable, Decoding, Finishable

  enum :status, { open: "open", completed: "completed", stood_down: "stood_down", timed_out: "timed_out" }, validate: true

  belongs_to :user
  belongs_to :mission

  has_secure_token :token, length: 32

  before_validation -> { self.started_at ||= Time.current }, on: :create

  # Starts a mission, or resumes the one in progress. An attempt left idle too long is closed first, so the
  # player gets a fresh mission rather than a debrief for one they walked away from.
  def self.start(user:, mission:)
    user.mission_attempts.open.where(mission:).each(&:expire_if_stale)
    user.mission_attempts.open.find_or_create_by!(mission:) { |attempt| attempt.relaxed = user.relaxed_mode }
  rescue ActiveRecord::RecordNotUnique
    user.mission_attempts.open.find_by!(mission:)
  end

  def to_param
    token
  end

  # --- Progress (see Rewarded) ---------------------------------------------------------

  include Rewarded

  def side = "blue"
  def xp_reason = :mission_completed
  def finished_at = completed_at

  # Finished just now by playing it: an attempt that expired doesn't count as a day played.
  def just_finished?
    saved_change_to_status? && (completed? || stood_down?)
  end
end
