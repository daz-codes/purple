# A player's run through a shift. Created on the server with a random token; every action goes
# through Shift::Engine, which records it in the log and moves the clock on.
#
# The query methods below describe what the player can already see (which messages have arrived,
# which they've opened, expanded, verified or reported). They never answer whether a message is
# phishing.
class ShiftAttempt < ApplicationRecord
  enum :status, { open: "open", completed: "completed", timed_out: "timed_out" }, validate: true

  belongs_to :user
  belongs_to :shift
  has_many :attempt_actions, -> { order(:id) }, dependent: :delete_all, inverse_of: :shift_attempt

  has_secure_token :token, length: 32

  scope :finished, -> { where.not(status: :open) }
  scope :scored, -> { where(scored: true) }

  before_validation -> { self.started_at ||= Time.current }, on: :create

  validates :clock_minutes, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :clock_within_time_budget

  def self.start(user:, shift:)
    user.shift_attempts.open.find_or_create_by!(shift:)
  rescue ActiveRecord::RecordNotUnique
    user.shift_attempts.open.find_by!(shift:)
  end

  def to_param
    token
  end

  def finished?
    !open?
  end

  def time_budget
    shift.time_budget_minutes
  end

  def minutes_left
    time_budget - clock_minutes
  end

  # Messages that have landed in the inbox so far, newest first, as a mail client shows them.
  def arrived_messages
    shift.messages.where(arrives_at_minute: ..clock_minutes).reorder(arrives_at_minute: :desc, position: :desc)
  end

  def inbox_messages
    arrived_messages.reject { |message| reported?(message) }
  end

  def find_arrived_message(public_ref)
    arrived_messages.find_by_public_ref(public_ref)
  end

  def next_arrival_minute
    shift.messages.where(arrives_at_minute: (clock_minutes + 1)..).minimum(:arrives_at_minute)
  end

  # The message in the reading pane: the last one opened, unless it has since been reported.
  def current_message
    key = actions.reverse_each.find(&:open_message?)&.target_key
    message = shift.messages.find_by(key:) if key
    message unless message.nil? || reported?(message)
  end

  def opened?(message) = done?(:open_message, message.key)
  def headers_expanded?(message) = done?(:expand_headers, message.key)
  def sender_verified?(message) = done?(:verify_sender, message.key)
  def reported?(message) = done?(:report_message, message.key)
  def task_completed?(task) = done?(:complete_task, task.key)

  def task_overdue?(task)
    !task_completed?(task) && clock_minutes > task.due_at_minute
  end

  def actions
    @actions ||= attempt_actions.to_a
  end

  def scoring
    Scoring::Calculator.new(shift:, actions:)
  end

  def reload(*)
    @actions = nil
    @done = nil
    super
  end

  private
    def done?(kind, target_key)
      @done ||= actions.each_with_object(Set.new) { |action, done| done << [ action.kind, action.target_key ] }
      @done.include?([ kind.to_s, target_key ])
    end

    def clock_within_time_budget
      errors.add(:clock_minutes, "can't run past the end of the shift") if shift && clock_minutes.to_i > time_budget
    end
end
