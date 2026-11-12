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

  test "the clock can't run past the shift's time budget" do
    attempt = ShiftAttempt.start(user: users(:one), shift: shifts(:month_end))

    assert_not attempt.update(clock_minutes: 31)
  end

  test "scores are only set once the shift is over" do
    attempt = ShiftAttempt.start(user: users(:one), shift: shifts(:month_end))

    assert_raises(ActiveRecord::StatementInvalid) { attempt.update_columns(score: 10) }
  end

  test "messages are found by their opaque ref, never by their key or position" do
    attempt = ShiftAttempt.start(user: users(:one), shift: shifts(:month_end))
    ref = attempt.message_ref(messages(:real_invoice))

    assert_match(/\A\h{16}\z/, ref)
    assert_equal messages(:real_invoice), attempt.find_arrived_message(ref)
    assert_nil attempt.find_arrived_message("real_invoice")
    assert_nil attempt.find_arrived_message("m1")
    assert_nil attempt.find_arrived_message(attempt.message_ref(messages(:fake_invoice))) # hasn't arrived yet
  end

  test "message refs survive re-ordering and differ between attempts" do
    attempt = ShiftAttempt.start(user: users(:one), shift: shifts(:month_end))
    ref = attempt.message_ref(messages(:real_invoice))
    messages(:real_invoice).update!(position: 99)

    assert_equal messages(:real_invoice), attempt.reload.find_arrived_message(ref)
    other = ShiftAttempt.start(user: users(:two), shift: shifts(:month_end))
    assert_not_equal ref, other.message_ref(messages(:real_invoice))
  end

  test "the time budget is copied from the shift when the attempt starts" do
    attempt = ShiftAttempt.start(user: users(:one), shift: shifts(:month_end))
    shifts(:month_end).update!(time_budget_minutes: 10)

    assert_equal 30, attempt.reload.time_budget
    assert attempt.update(clock_minutes: 20)
  end
end
