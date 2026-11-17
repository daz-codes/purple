require "application_system_test_case"

class HomeTest < ApplicationSystemTestCase
  test "visitor sees both sides of the game" do
    visit root_path

    assert_selector "h1", text: "Attack. Defend. Debrief."
    assert_text "Work a mission"
    assert_text "Red's Workshop"
    assert_text "See both sides of every move"
  end

  test "the footer leads to the privacy and terms pages" do
    visit root_path
    within("footer") { click_on "Privacy" }
    assert_selector "h1", text: "Privacy"

    within("footer") { click_on "Terms" }
    assert_selector "h1", text: "Terms of use"
  end

  test "the whole Blue card is a link to the tracks, and each track card is a link to its missions" do
    visit root_path
    find("a", text: "Work a mission").click
    assert_selector "h1", text: "Pick a track"

    track = Track.published.ordered.first
    find("a", text: track.title).click
    assert_selector "h1", text: track.title
  end
end
