# The in-game clock. Reading is free; checking things costs the shift's configured minutes. The
# day's length is copied from the shift when the attempt starts, so re-importing the shift with a
# shorter day can't strand an attempt that's already past the new end.
module ShiftAttempt::Clocked
  extend ActiveSupport::Concern

  included do
    before_validation -> { self.time_budget_minutes ||= shift&.time_budget_minutes }, on: :create

    validates :clock_minutes, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
    validates :time_budget_minutes, numericality: { only_integer: true, greater_than: 0 }
    validate :clock_within_time_budget
  end

  def time_budget
    time_budget_minutes
  end

  def minutes_left
    time_budget - clock_minutes
  end

  def time_up?
    minutes_left.zero?
  end

  def action_cost(kind)
    shift.action_cost(kind)
  end

  def affordable?(cost)
    cost <= minutes_left
  end

  private
    def advance_clock(minutes)
      self.clock_minutes += minutes
      save!
    end

    def clock_within_time_budget
      errors.add(:clock_minutes, "can't run past the end of the shift") if time_budget && clock_minutes.to_i > time_budget
    end
end
