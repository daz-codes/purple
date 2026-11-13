require "test_helper"

# Finishing a shift or launching a campaign brings the player's XP, streak and badges up to date.
class RewardedTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup { @user = users(:one) }

  test "finishing a scored shift earns its score as Blue XP, plus the day's streak bonus, and checks badges" do
    attempt = ShiftAttempt.start(user: @user, shift: shifts(:month_end))
    attempt.archive(messages(:newsletter))
    attempt.report(messages(:fake_invoice))

    assert_enqueued_with(job: AwardBadgesJob) { attempt.clock_off }

    reasons = @user.xp_events.map { |event| [ event.reason, event.amount ] }
    assert_equal [ [ "shift_completed", attempt.score ], [ "streak_bonus", 10 ] ], reasons
    assert_equal attempt.score + 10, @user.reload.blue_xp
    assert_equal 1, @user.current_streak
  end

  test "a replay earns no score XP, and only counts towards the streak on a new day" do
    ShiftAttempt.start(user: @user, shift: shifts(:month_end)).clock_off
    xp = @user.reload.blue_xp
    ShiftAttempt.start(user: @user, shift: shifts(:month_end)).clock_off

    assert_equal xp, @user.reload.blue_xp
  end

  test "launching a scored campaign earns Red XP" do
    campaign = RedCampaign.start(user: @user, target: targets(:month_end_target))
    %i[ bank_change spoof link sign_in friday ].each { |key| campaign.choose(target_options(key)) }
    campaign.launch

    assert_equal campaign.score + 10, @user.reload.red_xp
  end

  test "unconfirmed players and expired attempts earn nothing" do
    attempt = ShiftAttempt.start(user: users(:unconfirmed), shift: shifts(:month_end))
    assert_no_enqueued_jobs(only: AwardBadgesJob) { attempt.clock_off }
    assert_equal 0, users(:unconfirmed).reload.xp_total

    expired = ShiftAttempt.start(user: @user, shift: shifts(:month_end))
    travel ShiftAttempt::Timed::EXPIRES_AFTER + 1.second
    assert_no_enqueued_jobs(only: AwardBadgesJob) { expired.expire_if_stale }
    assert_equal 0, @user.reload.xp_total
  end
end
