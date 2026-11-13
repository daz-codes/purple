require "test_helper"

class ProgressHelperTest < ActionView::TestCase
  setup do
    Current.session = users(:one).sessions.create!
  end

  test "a shift left open until it closed says why it earned nothing, rather than calling it a replay" do
    attempt = ShiftAttempt.start(user: users(:one), shift: shifts(:month_end))
    attempt.update!(status: :timed_out, completed_at: Time.current, scored: false, score: 0)

    assert_equal "This shift was left open until it closed, so it doesn't earn XP.", xp_note(attempt)
  end

  test "a finished replay is called a replay" do
    attempt = ShiftAttempt.start(user: users(:one), shift: shifts(:month_end))
    attempt.update!(status: :completed, completed_at: Time.current, scored: false, score: 10)

    assert_equal "This replay doesn't earn XP: only your first finished attempt does.", xp_note(attempt)
  end
end
