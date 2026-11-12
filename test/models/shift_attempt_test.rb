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
      ShiftAttempt.new(user: users(:one), shift: shifts(:month_end), started_at: Time.current).save!(validate: false)
    end
  end

  test "the clock can't run past the shift's time budget" do
    attempt = ShiftAttempt.start(user: users(:one), shift: shifts(:month_end))

    assert_not attempt.update(clock_minutes: 31)
  end

  test "scores are only set once the shift is over" do
    attempt = ShiftAttempt.start(user: users(:one), shift: shifts(:month_end))

    assert_raises(ActiveRecord::StatementInvalid) { attempt.update_columns(score: 10) }
  end

  test "messages are found by their neutral public ref, never by their key" do
    attempt = ShiftAttempt.start(user: users(:one), shift: shifts(:month_end))

    assert_equal messages(:real_invoice), attempt.find_arrived_message("m1")
    assert_nil attempt.find_arrived_message("real_invoice")
    assert_nil attempt.find_arrived_message("m2") # hasn't arrived yet
  end
end
