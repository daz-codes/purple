require "application_system_test_case"

class HomeTest < ApplicationSystemTestCase
  test "visitor sees both sides of the game" do
    visit root_path

    assert_selector "h1", text: "Attack. Defend. Debrief."
    assert_text "Work a shift"
    assert_text "Red's Workshop"
    assert_text "See both sides of every move"
  end

  test "the whole Blue card is a link to the tracks, and each track card is a link to its shifts" do
    visit root_path
    find("a", text: "Work a shift").click
    assert_selector "h1", text: "Pick a track"

    track = Track.published.ordered.first
    find("a", text: track.title).click
    assert_selector "h1", text: track.title
  end
end
