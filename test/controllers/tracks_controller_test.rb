require "test_helper"

class TracksControllerTest < ActionDispatch::IntegrationTest
  test "anyone can browse tracks and read a briefing" do
    get tracks_path
    assert_response :success
    assert_select "h2", text: "Basics"

    get track_path(tracks(:basics))
    assert_response :success
    assert_select "h2", text: "Month-end"

    get mission_path(missions(:month_end))
    assert_response :success
    assert_select "a", text: "Sign in to play"
  end

  test "sign in to play returns to the briefing, and just viewing a briefing doesn't" do
    get mission_path(missions(:month_end))
    post session_path, params: { email_address: users(:one).email_address, password: "correct horse battery" }
    assert_redirected_to root_url
    delete session_path

    get new_mission_attempt_path(missions(:month_end))
    assert_redirected_to new_session_path
    post session_path, params: { email_address: users(:one).email_address, password: "correct horse battery" }
    assert_redirected_to new_mission_attempt_url(missions(:month_end))
    follow_redirect!
    assert_redirected_to mission_path(missions(:month_end))
  end

  test "the track page shows each mission's best finished attempt, with its stars and score" do
    sign_in_as users(:one)
    get track_path(tracks(:basics))
    assert_select "[data-testid=mission-progress]", count: 0

    worse = MissionAttempt.start(user: users(:one), mission: missions(:month_end))
    worse.stand_down # nothing done: 0
    best = MissionAttempt.start(user: users(:one), mission: missions(:month_end))
    best.archive(messages(:newsletter))
    best.report(messages(:fake_invoice))
    best.stand_down # +10 + 30, then -20 for the invoice left unapproved = 20 (the thank-you only needed archiving)

    get track_path(tracks(:basics))
    assert_select "[data-testid=mission-progress]" do
      assert_select "*", text: /Stood down/
      assert_select "strong", text: "20"
      assert_select "*", text: /out of 145/ # 105 from the messages, plus up to 40 speed bonus
      assert_select "[data-testid=stars][aria-label='0 of 3 stars']"
      assert_select "a[href=?]", mission_attempt_path(best), text: "See debrief"
    end
  end

  test "an attempt left open too long says so" do
    sign_in_as users(:one)
    attempt = MissionAttempt.start(user: users(:one), mission: missions(:month_end))
    travel MissionAttempt::Timed::EXPIRES_AFTER + 1.second
    attempt.expire_if_stale
    assert attempt.timed_out?

    get track_path(tracks(:basics))
    assert_select "[data-testid=mission-progress]", text: /Left unfinished/
  end

  test "an unfinished attempt doesn't count as completed" do
    sign_in_as users(:one)
    MissionAttempt.start(user: users(:one), mission: missions(:month_end))

    get track_path(tracks(:basics))
    assert_select "[data-testid=mission-progress]", count: 0
  end

  test "unpublished missions aren't found" do
    missions(:month_end).update!(published: false)

    get mission_path(missions(:month_end))
    assert_response :not_found
  end
end
