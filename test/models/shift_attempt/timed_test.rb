require "test_helper"

class ShiftAttempt::TimedTest < ActiveSupport::TestCase
  setup do
    travel_to Time.zone.local(2026, 11, 13, 9, 0, 0)
    @attempt = ShiftAttempt.start(user: users(:one), shift: shifts(:month_end))
  end

  test "time is real time since the start, plus penalties, and every move is stamped with it" do
    travel 90.seconds
    @attempt.verify_sender(messages(:real_invoice))
    travel 10.seconds
    @attempt.read(messages(:newsletter))

    assert_equal [ [ 90, 30 ], [ 130, 0 ] ], @attempt.actions.map { |action| [ action.at_seconds, action.penalty_seconds ] }
    assert_equal 130, @attempt.elapsed_seconds
  end

  test "a finished attempt's time stops when it finished" do
    travel 60.seconds
    @attempt.give_up
    travel 1.hour

    assert_equal 60, @attempt.reload.elapsed_seconds
  end

  test "an attempt left open for two hours expires, and can't be played" do
    travel 2.hours + 1.second
    assert @attempt.stale?
    assert_raises(ShiftAttempt::Rejected, match: /over/) { @attempt.read(messages(:newsletter)) }

    @attempt.expire_if_stale
    assert @attempt.reload.timed_out?
  end

  test "relaxed mode is copied from the player when the attempt starts" do
    users(:two).update!(relaxed_mode: true)

    assert ShiftAttempt.start(user: users(:two), shift: shifts(:month_end)).relaxed?
    assert_not @attempt.relaxed?
  end
end
