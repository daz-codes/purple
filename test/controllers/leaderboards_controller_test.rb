require "test_helper"

class LeaderboardsControllerTest < ActionDispatch::IntegrationTest
  setup do
    users(:two).xp_events.create!(side: "blue", amount: 300, reason: :shift_completed, occurred_at: Time.current)
    users(:one).xp_events.create!(side: "blue", amount: 100, reason: :shift_completed, occurred_at: Time.current)
  end

  test "anyone can see the board, with links to profiles" do
    get leaderboard_path(side: "blue")

    assert_response :success
    assert_select "[data-testid=leaderboard] tr", count: 2
    assert_select "[data-testid=leaderboard] a[href=?]", profile_path("red_two"), text: "red_two"
    assert_select "a[aria-current=page]", text: "Blue"
  end

  test "a signed-in player always sees their own rank" do
    sign_in_as users(:one)
    get leaderboard_path(side: "blue")

    assert_select "[data-testid=my-rank]", text: /ranked 2nd with 100 XP/
  end

  test "an empty board says so" do
    get leaderboard_path(side: "red")

    assert_select "p", text: /Nobody's on this board yet/
  end
end
