require "test_helper"

class PagesControllerTest < ActionDispatch::IntegrationTest
  test "visitors get the introduction" do
    get root_path

    assert_response :success
    assert_select "h1", text: /Attack. Defend. Debrief./
  end

  test "the privacy and terms pages are public, name who runs Purple and have nothing left to fill in" do
    { privacy_path => "Privacy", terms_path => "Terms of use" }.each do |path, heading|
      get path

      assert_response :success
      assert_select "h1", text: heading
      assert_select "a[href=?]", "mailto:privacy@purple.daz.codes"
      assert_includes response.body, "Darren Jones"
      assert_not_includes response.body, "[to confirm"
    end
  end

  test "every page links to the privacy and terms pages, and sign-up mentions them" do
    get new_registration_path

    assert_select "footer a[href=?]", privacy_path
    assert_select "footer a[href=?]", terms_path
    assert_select "form a[href=?]", terms_path
    assert_select "form a[href=?]", privacy_path
  end

  test "sends a strict content security policy" do
    get root_path
    csp = response.headers["Content-Security-Policy"]

    assert_includes csp, "frame-ancestors 'none'"
    assert_includes csp, "object-src 'none'"
    assert_match(/script-src 'self' 'nonce-[^']+'/, csp)
    assert_no_match(/unsafe-inline|unsafe-eval/, csp)
  end

  test "players get their dashboard: both sides' levels, their streak, a side switcher and their badges" do
    user = users(:one)
    user.award_xp(side: "blue", amount: 150, reason: :mission_completed)
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

  test "the dashboard suggests the next mission and target the player hasn't finished" do
    MissionAttempt.start(user: users(:one), mission: missions(:month_end)).stand_down
    sign_in_as users(:one)

    get root_path
    assert_select "[data-testid=blue-suggestion]", text: /Site visit/
    assert_select "[data-testid=red-suggestion]", text: /Month-end at Larkhill/
  end

  test "the dashboard offers to resume a mission in progress" do
    attempt = MissionAttempt.start(user: users(:one), mission: missions(:month_end))
    sign_in_as users(:one)

    get root_path
    assert_select "a[href=?]", mission_attempt_path(attempt), text: /Resume/
  end
end
