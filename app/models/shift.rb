# One playable round for Blue: a simulated working day with an inbox, a task list and a clock.
# For the MVP every shift is authored by the system playing Red.
class Shift < ApplicationRecord
  # Minutes each action costs on the in-game clock. A shift can override any of these.
  DEFAULT_ACTION_COSTS = {
    "open_message" => 0, "hover_link" => 0, "expand_headers" => 1, "verify_sender" => 5,
    "report_message" => 1, "complete_task" => 2, "use_hint" => 0
  }.freeze

  enum :kind, { inbox: "inbox", messages: "messages" }, prefix: true, validate: true
  enum :difficulty, { beginner: "beginner", intermediate: "intermediate", advanced: "advanced" }, validate: true
  enum :author_side, { red: "red" }, prefix: :authored_by, validate: true
  enum :author_type, { system: "system", player: "player" }, prefix: :authored_by, validate: true

  belongs_to :track
  has_many :tasks, -> { order(:due_at_minute, :id) }, dependent: :destroy
  has_many :messages, -> { order(:position) }, dependent: :destroy
  has_many :hints, -> { order(:position) }, dependent: :destroy
  has_many :shift_attempts, dependent: :restrict_with_exception

  scope :published, -> { where(published: true) }

  validates :slug, presence: true, uniqueness: true
  validates :title, :briefing, :learning_summary, presence: true
  validates :time_budget_minutes, numericality: { only_integer: true, greater_than: 0 }
  validate :action_costs_are_known_non_negative_integers

  def action_cost(kind)
    DEFAULT_ACTION_COSTS.merge(action_costs).fetch(kind.to_s, 0)
  end

  def to_param
    slug
  end

  private
    def action_costs_are_known_non_negative_integers
      action_costs.each do |kind, cost|
        errors.add(:action_costs, "has an unknown action: #{kind}") unless DEFAULT_ACTION_COSTS.key?(kind)
        errors.add(:action_costs, "must be whole minutes, 0 or more (#{kind})") unless cost.is_a?(Integer) && cost >= 0
      end
    end
end
