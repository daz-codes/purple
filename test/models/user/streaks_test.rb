require "test_helper"

# Days are calendar days in Europe/London.
class User::StreaksTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @source = ShiftAttempt.start(user: @user, shift: shifts(:month_end))
  end

  test "the first play of a day starts a streak and earns the bonus; later plays that day don't" do
    assert record("2026-11-10 09:00")
    assert_nil record("2026-11-10 18:00")

    assert_equal [ 1, 1, Date.new(2026, 11, 10) ], @user.reload.values_at(:current_streak, :longest_streak, :last_played_on)
    assert_equal 10, @user.blue_xp
  end

  test "consecutive days extend the streak; missing a day starts again, and the longest is kept" do
    record("2026-11-10 09:00", "2026-11-11 09:00", "2026-11-12 09:00")
    assert_equal [ 3, 3 ], @user.reload.values_at(:current_streak, :longest_streak)

    record("2026-11-14 09:00")
    assert_equal [ 1, 3 ], @user.reload.values_at(:current_streak, :longest_streak)
  end

  test "midnight is London's: in summer, 23:30 UTC is already the next day" do
    record("2026-07-01 22:30 UTC") # 23:30 in London: the 1st
    record("2026-07-01 23:30 UTC") # 00:30 in London: the 2nd

    assert_equal [ 2, Date.new(2026, 7, 2) ], @user.reload.values_at(:current_streak, :last_played_on)
  end

  test "in winter London is on UTC, so 23:30 UTC is still the same day" do
    record("2026-12-01 09:00 UTC", "2026-12-01 23:30 UTC")

    assert_equal [ 1, Date.new(2026, 12, 1) ], @user.reload.values_at(:current_streak, :last_played_on)
  end

  test "the streak shown today has lapsed once a whole day has gone by unplayed" do
    record("2026-11-10 09:00", "2026-11-11 09:00")

    assert_equal 2, @user.reload.streak_today(today: Date.new(2026, 11, 11))
    assert_equal 2, @user.streak_today(today: Date.new(2026, 11, 12))
    assert_equal 0, @user.streak_today(today: Date.new(2026, 11, 13))
  end

  test "the streak bonus goes to the side played first that day" do
    @user.record_play(side: "red", source: @source, at: Time.zone.parse("2026-11-10 09:00"))

    assert_equal [ 0, 10 ], @user.reload.values_at(:blue_xp, :red_xp)
  end

  private
    def record(*times)
      times.map { |time| @user.record_play(side: "blue", source: ShiftAttempt.new(id: rand(1_000_000)), at: Time.zone.parse(time)) }.last
    end
end
