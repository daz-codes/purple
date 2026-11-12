require "test_helper"

class ShiftAttemptTest < ActiveSupport::TestCase
  test "starting creates an open attempt with a random token, or resumes the open one" do
    attempt = ShiftAttempt.start(user: users(:one), shift: shifts(:month_end))

    assert attempt.open?
    assert_equal 32, attempt.token.length
    assert_equal attempt.token, attempt.to_param
    assert_equal attempt, ShiftAttempt.start(user: users(:one), shift: shifts(:month_end))
    assert_not_equal attempt, ShiftAttempt.start(user: users(:two), shift: shifts(:month_end))
  end

  test "the database allows only one open attempt per player and shift" do
    ShiftAttempt.start(user: users(:one), shift: shifts(:month_end))

    assert_raises(ActiveRecord::RecordNotUnique) do
      ShiftAttempt.new(user: users(:one), shift: shifts(:month_end), started_at: Time.current, time_budget_minutes: 30).save!(validate: false)
    end
  end
end
