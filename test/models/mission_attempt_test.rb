require "test_helper"

class MissionAttemptTest < ActiveSupport::TestCase
  test "starting creates an open attempt with a random token, or resumes the open one" do
    attempt = MissionAttempt.start(user: users(:one), mission: missions(:month_end))

    assert attempt.open?
    assert_equal 32, attempt.token.length
    assert_equal attempt.token, attempt.to_param
    assert_equal attempt, MissionAttempt.start(user: users(:one), mission: missions(:month_end))
    assert_not_equal attempt, MissionAttempt.start(user: users(:two), mission: missions(:month_end))
  end

  test "the database allows only one open attempt per player and mission" do
    MissionAttempt.start(user: users(:one), mission: missions(:month_end))

    assert_raises(ActiveRecord::RecordNotUnique) do
      MissionAttempt.new(user: users(:one), mission: missions(:month_end), started_at: Time.current).save!(validate: false)
    end
  end
end
