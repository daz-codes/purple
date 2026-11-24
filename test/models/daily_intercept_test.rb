require "test_helper"

class DailyInterceptTest < ActiveSupport::TestCase
  setup do
    @second = Mission.create!(track: tracks(:daily), slug: "daily-two", title: "Second", kind: "signals", difficulty: "beginner",
                              par_minutes: 5, position: 2, published: true, briefing: "x", learning_summary: "x")
  end

  test "is the same for everyone on a day, and works through the pool" do
    day = Date.new(2026, 11, 17)
    assert_equal DailyIntercept.new(day:).mission, DailyIntercept.new(day:).mission
    assert_equal [ missions(:daily_drizzle), @second ].to_set, [ day, day + 1 ].map { |date| DailyIntercept.new(day: date).mission }.to_set
  end

  test "is nothing when the pool is empty" do
    Track.where(daily: true).update_all(published: false)
    assert_nil DailyIntercept.new.mission
  end

  test "knows whether the player finished today's" do
    daily = DailyIntercept.new
    assert_not daily.done_by?(users(:one))
    assert_not daily.done_by?(nil)

    MissionAttempt.start(user: users(:one), mission: daily.mission).stand_down
    assert daily.done_by?(users(:one))
    assert_not DailyIntercept.new(day: daily.day + 1).done_by?(users(:one))
  end
end
