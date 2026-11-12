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

  test "unpublished shifts aren't found" do
    shifts(:month_end).update!(published: false)

    get shift_path(shifts(:month_end))
    assert_response :not_found
  end
end
