# One thing a player did during a shift. The log is append-only: it drives the clock and the
# scoring, and from M5 it is replayed in the Purple debrief.
#
# target_key holds server-side keys (a message's authored key, a task's key), so the log itself is
# never sent to the browser.
class AttemptAction < ApplicationRecord
  KINDS = %w[
    open_message expand_headers verify_sender hover_link click_link close_landing submit_credentials
    open_attachment report_message flag_element complete_task use_hint wait end_shift
  ].freeze

  enum :kind, KINDS.index_by(&:itself), validate: true

  belongs_to :shift_attempt

  validates :minute, :cost_minutes, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  def readonly?
    persisted? || super
  end

  # The minute on the clock when the action finished.
  def finished_at_minute
    minute + cost_minutes
  end
end
