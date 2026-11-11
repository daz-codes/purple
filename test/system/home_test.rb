require "application_system_test_case"

class HomeTest < ApplicationSystemTestCase
  test "visitor sees both sides of the game" do
    visit root_path

    assert_selector "h1", text: "Attack. Defend. Debrief."
    assert_text "Work a shift"
    assert_text "Red's Workshop"
    assert_text "See both sides of every move"
  end
end
