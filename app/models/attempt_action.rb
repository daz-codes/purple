# One thing a player did during a shift. The log is append-only: it drives arrivals and the scoring,
# and it's replayed in the Purple debrief.
#
# at_seconds is the attempt's elapsed time when the move was made (real time plus earlier penalties);
# penalty_seconds is any time the move itself added, such as the 30 seconds a call-back takes.
#
# target_key holds a message's authored key, so the log itself is never sent to the browser.
class AttemptAction < ApplicationRecord
  KINDS = %w[
    open_message expand_headers verify_sender click_link close_landing submit_credentials open_attachment
    run_download use_portal report_message archive_message flag_element send_reply use_hint give_up
  ].freeze

  # Moves that finish with a message: it leaves the inbox and counts as dealt with.
  HANDLING_KINDS = %w[ report_message archive_message ].freeze

  enum :kind, KINDS.index_by(&:itself), validate: true

  belongs_to :shift_attempt

  validates :at_seconds, :penalty_seconds, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  def readonly?
    persisted? || super
  end

  def handling?
    kind.in?(HANDLING_KINDS)
  end

  def minute
    at_seconds / 60
  end
end
