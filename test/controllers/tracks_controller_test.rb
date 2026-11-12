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

  test "unpublished shifts aren't found" do
    shifts(:month_end).update!(published: false)

    get shift_path(shifts(:month_end))
    assert_response :not_found
  end
end
