require "test_helper"

# The fixture shift is 30 minutes long. real_invoice arrives at minute 0; fake_invoice at minute 3.
class ShiftAttempt::ClockedTest < ActiveSupport::TestCase
  setup do
    @attempt = ShiftAttempt.start(user: users(:one), shift: shifts(:month_end))
  end

  test "reading is free and checking costs the shift's configured minutes" do
    @attempt.read(messages(:real_invoice))
    assert_equal 0, @attempt.clock_minutes

    @attempt.expand_headers(messages(:real_invoice))
    assert_equal 1, @attempt.clock_minutes

    @attempt.verify_sender(messages(:real_invoice))
    assert_equal 6, @attempt.clock_minutes

    @attempt.report(messages(:fake_invoice))
    assert_equal 7, @attempt.clock_minutes
  end

  test "a shift can override action costs" do
    shifts(:month_end).update!(action_costs: { "expand_headers" => 4 })

    @attempt.expand_headers(messages(:real_invoice))
    assert_equal 4, @attempt.clock_minutes
  end

  test "moves that don't fit in the time left are rejected" do
    @attempt.update!(clock_minutes: 27)

    assert_raises(ShiftAttempt::Rejected, match: /takes 5 min and you have 3/) { @attempt.verify_sender(messages(:real_invoice)) }
    assert_equal 27, @attempt.reload.clock_minutes
  end

  test "the shift times out when the clock reaches the budget, and later moves are rejected" do
    @attempt.update!(clock_minutes: 25)
    @attempt.verify_sender(messages(:real_invoice))

    assert @attempt.timed_out?
    assert_equal 30, @attempt.clock_minutes
    assert_not_nil @attempt.completed_at
    assert_raises(ShiftAttempt::Rejected, match: /over/) { @attempt.read(messages(:real_invoice)) }
  end

  test "the clock can't run past the time budget" do
    assert_not @attempt.update(clock_minutes: 31)
  end

  test "the time budget is copied from the shift when the attempt starts" do
    shifts(:month_end).update!(time_budget_minutes: 10)

    assert_equal 30, @attempt.reload.time_budget
    assert @attempt.update(clock_minutes: 20)
  end

  test "an attempt plays to the time budget it started with" do
    shifts(:month_end).update!(time_budget_minutes: 10)
    @attempt.wait_for_mail # to minute 3
    @attempt.update_columns(clock_minutes: 15)
    @attempt.reload

    assert_nothing_raised { @attempt.expand_headers(messages(:real_invoice)) }
    @attempt.end_shift
    assert @attempt.completed?
  end
end
