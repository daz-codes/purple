require "test_helper"

class ShiftAttempt::FinishableTest < ActiveSupport::TestCase
  setup do
    @attempt = ShiftAttempt.start(user: users(:one), shift: shifts(:month_end))
  end

  test "the shift ends by itself once every message has been dealt with, including the ones that arrive on the way" do
    @attempt.archive(messages(:newsletter))     # brings the fake invoice
    @attempt.report(messages(:fake_invoice))
    assert @attempt.open?

    @attempt.archive(messages(:real_invoice))   # brings the thank-you
    assert @attempt.open?

    @attempt.archive(messages(:supplier_thanks))
    assert @attempt.completed?
    assert @attempt.completed_at
    assert @attempt.scored?
    assert_equal @attempt.scorecard.total, @attempt.score
  end

  test "giving up ends the shift, and what's left counts as ignored" do
    @attempt.give_up

    assert @attempt.gave_up?
    assert_equal "give_up", @attempt.actions.last.kind
    assert_equal :not_done, @attempt.scorecard.message_result_for("real_invoice").outcome
    assert_equal :never_arrived, @attempt.scorecard.message_result_for("fake_invoice").outcome
    assert_raises(ShiftAttempt::Rejected, match: /over/) { @attempt.give_up }
  end

  test "only a confirmed player's first finished attempt is scored" do
    @attempt.give_up
    second = ShiftAttempt.start(user: users(:one), shift: shifts(:month_end))
    second.give_up

    assert @attempt.scored?
    assert_not second.scored?
  end

  test "the best attempt at each shift, for the track page" do
    @attempt.give_up

    assert_equal({ shifts(:month_end).id => @attempt }, ShiftAttempt.where(user: users(:one)).best_by_shift([ shifts(:month_end) ]))
  end
end
