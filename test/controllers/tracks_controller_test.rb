require "test_helper"

class TracksControllerTest < ActionDispatch::IntegrationTest
  test "anyone can browse tracks and read a briefing" do
    get tracks_path
    assert_response :success
    assert_select "h2", text: "Basics"

    get track_path(tracks(:basics))
    assert_response :success
    assert_select "h2", text: "Month-end"

    get shift_path(shifts(:month_end))
    assert_response :success
    assert_select "a", text: "Sign in to play"
  end

  test "sign in to play returns to the briefing, and just viewing a briefing doesn't" do
    get shift_path(shifts(:month_end))
    post session_path, params: { email_address: users(:one).email_address, password: "correct horse battery" }
    assert_redirected_to root_url
    delete session_path

    get new_shift_attempt_path(shifts(:month_end))
    assert_redirected_to new_session_path
    post session_path, params: { email_address: users(:one).email_address, password: "correct horse battery" }
    assert_redirected_to new_shift_attempt_url(shifts(:month_end))
    follow_redirect!
    assert_redirected_to shift_path(shifts(:month_end))
  end

  test "the track page shows each shift's best finished attempt, with its stars and score" do
    sign_in_as users(:one)
    get track_path(tracks(:basics))
    assert_select "[data-testid=shift-progress]", count: 0

    worse = ShiftAttempt.start(user: users(:one), shift: shifts(:month_end))
    worse.end_shift # -20, so 0
    best = ShiftAttempt.start(user: users(:one), shift: shifts(:month_end))
    best.wait_for_mail
    best.report(messages(:fake_invoice))
    best.end_shift # -20 + 30 = 10

    get track_path(tracks(:basics))
    assert_select "[data-testid=shift-progress]" do
      assert_select "*", text: /Completed/
      assert_select "strong", text: "10"
      assert_select "*", text: /out of 80/
      assert_select "[data-testid=stars][aria-label='0 of 3 stars']"
      assert_select "a[href=?]", shift_attempt_path(best), text: "See debrief"
    end
  end

  test "a best attempt that ran out of time says so" do
    sign_in_as users(:one)
    attempt = ShiftAttempt.start(user: users(:one), shift: shifts(:month_end))
    attempt.update_columns(clock_minutes: 30)
    attempt.reload.end_shift
    assert attempt.timed_out?

    get track_path(tracks(:basics))
    assert_select "[data-testid=shift-progress]", text: /Ran out of time/
  end

  test "an unfinished attempt doesn't count as completed" do
    sign_in_as users(:one)
    ShiftAttempt.start(user: users(:one), shift: shifts(:month_end))

    get track_path(tracks(:basics))
    assert_select "[data-testid=shift-progress]", count: 0
  end

  test "unpublished shifts aren't found" do
    shifts(:month_end).update!(published: false)

    get shift_path(shifts(:month_end))
    assert_response :not_found
  end
end
