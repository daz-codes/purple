require "test_helper"

class ShiftAttempt::FinishableTest < ActiveSupport::TestCase
  setup do
    @attempt = ShiftAttempt.start(user: users(:one), shift: shifts(:month_end))
  end

  # Otherwise the clock (or the shift ending) would tell the player the report was wrong.
  test "reporting the only message that can complete a task gives nothing away" do
    @attempt.report(messages(:real_invoice))

    assert @attempt.open?
    assert_equal %w[ report_message ], @attempt.actions.map(&:kind)
    assert_not_includes @attempt.arrived_messages, messages(:fake_invoice)
  end

  test "ending the shift early leaves the phishes still to come unreported" do
    @attempt.end_shift # at minute 0: the phish is due at minute 3

    card = @attempt.scorecard
    assert_equal :arrived_after_shift, card.message_result_for("fake_invoice").outcome
    assert_equal 30, card.security_max
    assert_equal [ 0, 0 ], [ @attempt.security_score, @attempt.score ]
  end

  test "a task with no completing link doesn't end the shift" do
    links(:real_invoice_link).destroy!
    @attempt.read(messages(:real_invoice))

    assert @attempt.open?
  end

  test "ending the shift scores it from the log" do
    @attempt.wait_for_mail
    @attempt.report(messages(:fake_invoice))
    @attempt.end_shift

    assert @attempt.completed?
    assert_equal "end_shift", @attempt.actions.last.kind
    assert_equal [ -20, 30, 10 ], [ @attempt.productivity_score, @attempt.security_score, @attempt.score ]
  end

  test "scores are only set once the shift is over" do
    assert_raises(ActiveRecord::StatementInvalid) { @attempt.update_columns(score: 10) }
  end

  test "ending the shift doesn't finish it twice or lose first-attempt scoring" do
    # The clock is at the end of the day, so recording end_shift finishes the attempt by itself.
    @attempt.update_columns(clock_minutes: 30)
    @attempt.reload
    @attempt.end_shift

    assert @attempt.timed_out?
    assert @attempt.scored?
    assert_equal 1, @attempt.attempt_actions.where(kind: "end_shift").count
  end

  test "a finished shift can't be ended again" do
    @attempt.end_shift

    assert_raises(ShiftAttempt::Rejected, match: /over/) { @attempt.end_shift }
  end

  test "only a confirmed player's first finished attempt is scored" do
    @attempt.end_shift
    assert @attempt.scored?

    second = ShiftAttempt.start(user: users(:one), shift: shifts(:month_end))
    second.end_shift
    assert_not second.scored?

    unconfirmed = ShiftAttempt.start(user: users(:unconfirmed), shift: shifts(:month_end))
    unconfirmed.end_shift
    assert_not unconfirmed.scored?
  end
end
