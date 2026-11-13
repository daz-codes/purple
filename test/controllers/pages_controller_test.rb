require "test_helper"

class PagesControllerTest < ActionDispatch::IntegrationTest
  test "visitors get the introduction" do
    get root_path

    assert_response :success
    assert_select "h1", text: /Attack. Defend. Debrief./
  end

  test "players get their dashboard: both sides' levels, their streak, a side switcher and their badges" do
    user = users(:one)
    user.award_xp(side: "blue", amount: 150, reason: :shift_completed)
    user.update!(preferred_side: "blue", current_streak: 3, longest_streak: 5, last_played_on: User::Streaks.day_of(Time.current))
    user.user_badges.create!(badge: badges(:first_catch), awarded_at: Time.current)
    sign_in_as user

    get root_path

    assert_response :success
    assert_select "[data-testid=blue-progress] h2", text: "Level 2"
    assert_select "[data-testid=red-progress] h2", text: "Level 1"
    assert_select "[data-testid=streak]", text: /3 days in a row/
    assert_select "[aria-label='Your side'] button[aria-pressed=true]", text: "Blue"
    assert_select "[data-testid=badges] li[data-earned=true]", count: 1
    assert_select "[data-testid=badges] li", count: Badge.count
  end

  test "the dashboard offers to resume a shift in progress" do
    attempt = ShiftAttempt.start(user: users(:one), shift: shifts(:month_end))
    sign_in_as users(:one)

    get root_path
    assert_select "a[href=?]", shift_attempt_path(attempt), text: /Resume/
  end
end
