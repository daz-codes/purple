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
    assert_select "section#codebreaking" do
      assert_select "h3", text: "Encodings"
      assert_select "h3", text: "Intercept of the Day", count: 0
    end
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

  test "a locked track says what opens it, and opens once that's done" do
    sign_in_as users(:one)
    get paths_path
    assert_select "section#codebreaking a[href=?]", track_path(tracks(:ciphers)), text: /🔒 Finish 1 more mission on Encodings/

    MissionAttempt.start(user: users(:one), mission: missions(:kettle)).stand_down
    get paths_path
    assert_select "section#codebreaking a[href=?]", track_path(tracks(:ciphers)), text: /0 of 1 mission finished/
  end

  test "a locked path says so" do
    track = Track.create!(path: paths(:break_in), slug: "injection", title: "Injection", description: "x", difficulty: "beginner", published: true)
    Mission.create!(track:, slug: "open-door", title: "Open door", kind: "signals", difficulty: "beginner", par_minutes: 5,
                    published: true, briefing: "x", learning_summary: "x")
    get paths_path

    assert_select "section#break-in", text: /🔒 Locked/
    assert_select "section#break-in [data-testid=locked]", text: "Finish 3 more missions on any path to open Break-in."
  end

  test "the Intercept of the day is on top, and says when it's done" do
    get paths_path
    assert_select "[data-testid=daily-intercept][href=?]", mission_path(missions(:daily_drizzle)), text: /Crack it/

    sign_in_as users(:one)
    MissionAttempt.start(user: users(:one), mission: missions(:daily_drizzle)).stand_down
    get paths_path
    assert_select "[data-testid=daily-intercept]", text: /Done today ✓/
  end
end
