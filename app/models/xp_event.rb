# One entry in a player's XP ledger. Append-only: a side's XP is always the sum of its events, and the
# weekly leaderboards (M9) sum them by week. Each source (an attempt, a campaign, a badge) earns each
# kind of XP once.
class XpEvent < ApplicationRecord
  enum :side, { blue: "blue", red: "red" }, prefix: true, validate: true
  enum :reason, { shift_completed: "shift_completed", workshop_completed: "workshop_completed",
                  streak_bonus: "streak_bonus", badge_awarded: "badge_awarded" }, validate: true

  belongs_to :user
  belongs_to :source, polymorphic: true, optional: true

  validates :amount, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :occurred_at, presence: true

  def readonly?
    persisted? || super
  end
end
