require "test_helper"

class AwardBadgesJobTest < ActiveJob::TestCase
  include ActionCable::TestHelper

  test "awards new badges once, with their XP, and toasts each one" do
    user = users(:one)
    attempt = MissionAttempt.start(user:, mission: missions(:month_end))
    attempt.archive(messages(:newsletter))
    attempt.report(messages(:fake_invoice))
    attempt.stand_down
    xp = user.reload.blue_xp

    stream = [ user.to_gid_param, "notifications" ].join(":") # the name turbo_stream_from(user, :notifications) listens on
    assert_broadcasts(stream, 1) { AwardBadgesJob.perform_now(user, attempt) }
    assert_equal %w[ first_catch ], user.badges.pluck(:key)
    assert_equal xp + User::Badged::BADGE_XP, user.reload.blue_xp

    assert_no_broadcasts(stream) { AwardBadgesJob.perform_now(user, attempt) }
    assert_equal 1, user.user_badges.count
  end
end
