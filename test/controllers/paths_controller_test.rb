require "test_helper"

class PathsControllerTest < ActionDispatch::IntegrationTest
  test "anyone can see the paths, with tracks on the open ones and the rest coming soon" do
    get paths_path
    assert_response :success

    assert_select "[data-testid=path]", count: 3
    assert_select "section#phishing" do
      assert_select "h2", text: "Phishing"
      assert_select "h3", text: "Basics"
      assert_select "a[href=?]", track_path(tracks(:basics))
      assert_select "*", text: /Coming soon/, count: 0
      assert_select "[data-testid=path-progress]", count: 0
    end
    assert_select "section#codebreaking", text: /Coming soon/
    assert_select "section#break-in", text: /Coming soon/
  end

  test "a signed-in player sees how many missions they've finished on each path and track" do
    sign_in_as users(:one)
    get paths_path
    assert_select "section#phishing [data-testid=path-progress]", text: "0 of 2 missions finished"

    MissionAttempt.start(user: users(:one), mission: missions(:month_end)).stand_down
    MissionAttempt.start(user: users(:one), mission: missions(:month_end)) # open: doesn't count

    get paths_path
    assert_select "section#phishing [data-testid=path-progress]", text: "1 of 2 missions finished"
    assert_select "section#phishing a[href=?]", track_path(tracks(:basics)), text: /1 of 2 missions finished/
  end

  test "unpublished paths, and tracks with nothing published, aren't listed" do
    paths(:codebreaking).update!(published: false)
    Mission.update_all(published: false)
    get paths_path

    assert_select "section#codebreaking", count: 0
    assert_select "section#phishing", text: /Coming soon/
    assert_select "a[href=?]", track_path(tracks(:basics)), count: 0
  end

  test "the old track list redirects to the paths" do
    get "/tracks"
    assert_redirected_to "/paths"
  end
end
