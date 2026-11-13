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
    @attempt.clock_off
    travel 1.hour

    assert_equal 60, @attempt.reload.elapsed_seconds
  end

  test "an attempt left idle for two hours expires, can't be played, and doesn't use up the scored attempt" do
    travel 2.hours + 1.second
    assert @attempt.stale?
    assert_raises(ShiftAttempt::Rejected, match: /over/) { @attempt.read(messages(:newsletter)) }

    @attempt.expire_if_stale
    assert @attempt.reload.timed_out?
    assert_not @attempt.scored?
  end

  test "it's idle time that counts: a player still making moves after two hours carries on" do
    travel 1.hour + 50.minutes
    @attempt.read(messages(:newsletter))
    travel 1.hour

    assert_not @attempt.reload.stale?
    travel 1.hour + 1.second
    assert @attempt.reload.stale?
  end

  test "relaxed attempts aren't timed, but still expire when left idle" do
    users(:two).update!(relaxed_mode: true)
    relaxed = ShiftAttempt.start(user: users(:two), shift: shifts(:month_end))
    travel 2.hours + 1.second

    assert relaxed.stale?
  end

  test "an attempt that isn't stale is left alone without taking a lock" do
    assert_no_queries_match(/FOR UPDATE/) { @attempt.expire_if_stale }
  end

  test "starting again after walking away gives a fresh shift, not the old one's debrief" do
    travel 2.hours + 1.second
    fresh = ShiftAttempt.start(user: users(:one), shift: shifts(:month_end))

    assert fresh.open?
    assert_not_equal @attempt, fresh
    assert @attempt.reload.timed_out?
  end

  test "relaxed mode is copied from the player when the attempt starts" do
    users(:two).update!(relaxed_mode: true)

    assert ShiftAttempt.start(user: users(:two), shift: shifts(:month_end)).relaxed?
    assert_not @attempt.relaxed?
  end
end
