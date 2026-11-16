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

  test "an XP failure rolls completion and its final action back so finishing can be retried" do
    attempt = ShiftAttempt.start(user: @user, shift: shifts(:month_end))
    attempt.archive(messages(:newsletter))
    attempt.report(messages(:fake_invoice))

    # #record reloads the user association, so inject the failure for every instance of this user.
    user_id = @user.id
    callback = ->(event) { raise "XP unavailable" if event.user_id == user_id }
    XpEvent.set_callback(:create, :before, callback)
    begin
      assert_no_enqueued_jobs(only: AwardBadgesJob) do
        assert_raises(RuntimeError) { attempt.clock_off }
      end
    ensure
      XpEvent.skip_callback(:create, :before, callback)
    end

    assert attempt.reload.open?
    assert_empty attempt.result_content
    assert_not attempt.actions.any?(&:clock_off?)
    assert_equal 0, @user.reload.xp_total

    attempt.clock_off
    assert attempt.reload.scored?
    assert_equal attempt.score + User::Streaks::STREAK_BONUS, @user.reload.blue_xp
  end

  test "a failed Red reward leaves the draft available to launch again" do
    campaign = RedCampaign.start(user: @user, target: targets(:month_end_target))
    %i[ bank_change spoof link sign_in friday ].each { |key| campaign.choose(target_options(key)) }
    user_id = @user.id
    callback = ->(event) { raise "XP unavailable" if event.user_id == user_id }
    XpEvent.set_callback(:create, :before, callback)
    begin
      assert_raises(RuntimeError) { campaign.launch }
    ensure
      XpEvent.skip_callback(:create, :before, callback)
    end

    assert campaign.reload.draft?
    assert_equal 0, @user.reload.xp_total
    campaign.launch
    assert_equal campaign.score + User::Streaks::STREAK_BONUS, @user.reload.red_xp
  end
end
