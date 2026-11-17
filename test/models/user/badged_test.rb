require "test_helper"

class User::BadgedTest < ActiveSupport::TestCase
  test "a failed XP award rolls the badge back and can be retried" do
    user = users(:one)
    attempt = MissionAttempt.start(user:, mission: missions(:month_end))
    attempt.archive(messages(:newsletter))
    attempt.report(messages(:fake_invoice))
    attempt.stand_down
    xp = user.reload.xp_total

    original = user.method(:award_xp)
    begin
      user.define_singleton_method(:award_xp) { |**| raise "XP unavailable" }
      assert_raises(RuntimeError) { user.award_badges_for(attempt) }
    ensure
      user.define_singleton_method(:award_xp, original)
    end

    assert_empty user.reload.badges
    assert_equal xp, user.xp_total
    assert_equal %w[ first_catch ], user.award_badges_for(attempt).map(&:key)
    assert_equal xp + User::Badged::BADGE_XP, user.reload.xp_total
    assert_empty user.award_badges_for(attempt)
    assert_equal 1, user.xp_events.where(reason: :badge_awarded).count
  end
end
