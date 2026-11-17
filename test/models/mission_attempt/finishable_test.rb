require "test_helper"

class MissionAttempt::FinishableTest < ActiveSupport::TestCase
  setup do
    @attempt = MissionAttempt.start(user: users(:one), mission: missions(:month_end))
  end

  test "the mission ends by itself once every message has been dealt with, including the ones that arrive on the way" do
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

  test "standing down ends the mission, and what's left counts as ignored" do
    @attempt.stand_down

    assert @attempt.stood_down?
    assert_equal "stand_down", @attempt.actions.last.kind
    assert_equal :not_done, @attempt.scorecard.message_result_for("real_invoice").outcome
    assert_equal :never_arrived, @attempt.scorecard.message_result_for("fake_invoice").outcome
    assert_raises(MissionAttempt::Rejected, match: /over/) { @attempt.stand_down }
  end

  test "only a confirmed player's first finished attempt is scored" do
    @attempt.stand_down
    second = MissionAttempt.start(user: users(:one), mission: missions(:month_end))
    second.stand_down

    assert @attempt.scored?
    assert_not second.scored?
  end

  test "the best attempt at each mission, for the track page" do
    @attempt.stand_down

    assert_equal({ missions(:month_end).id => @attempt }, MissionAttempt.where(user: users(:one)).best_by_mission([ missions(:month_end) ]))
  end
end
