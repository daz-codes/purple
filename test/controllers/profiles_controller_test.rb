require "test_helper"

class ProfilesControllerTest < ActionDispatch::IntegrationTest
  test "a public profile shows both sides' levels, the preferred side and badges" do
    user = users(:one)
    user.award_xp(side: "red", amount: 120, reason: :workshop_completed)
    user.update!(preferred_side: "red")
    user.user_badges.create!(badge: badges(:fooled_carol), awarded_at: Time.current)

    get profile_path("blue_one")

    assert_response :success
    assert_select "[data-testid=red-level]", text: /Level 2/
    assert_select "[data-testid=blue-level]", text: /Level 1/
    assert_select "[data-testid=preferred-side]", text: "Prefers Red"
    assert_select "[data-testid=profile-badges] li", text: /Fooled Carol/
  end

  test "an unknown player isn't found" do
    get profile_path("nobody_here")

    assert_response :not_found
  end
end
