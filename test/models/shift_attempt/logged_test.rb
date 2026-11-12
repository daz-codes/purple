require "test_helper"

class ShiftAttempt::LoggedTest < ActiveSupport::TestCase
  setup do
    @attempt = ShiftAttempt.start(user: users(:one), shift: shifts(:month_end))
  end

  test "every move is logged with the minute it started and what it cost" do
    @attempt.expand_headers(messages(:real_invoice))
    @attempt.verify_sender(messages(:real_invoice))

    assert_equal [ [ "expand_headers", "real_invoice", 0, 1 ], [ "verify_sender", "real_invoice", 1, 5 ] ],
      @attempt.attempt_actions.reload.map { |action| [ action.kind, action.target_key, action.minute, action.cost_minutes ] }
  end

  test "the log is append-only" do
    action = @attempt.read(messages(:real_invoice))

    assert_raises(ActiveRecord::ReadOnlyRecord) { action.update!(minute: 5) }
  end

  test "a rejected move logs nothing" do
    assert_raises(ShiftAttempt::Rejected) { @attempt.read(messages(:fake_invoice)) }

    assert_empty @attempt.attempt_actions.reload
  end
end
