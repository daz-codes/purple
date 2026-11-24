require "application_system_test_case"

class PathsTest < ApplicationSystemTestCase
  test "a player finds a mission through its path and track, and comes back to see their progress" do
    sign_in users(:one)
    visit root_path
    within("nav[aria-label=Main]") { click_on "Paths" }

    assert_selector "h1", text: "Pick a path"
    within("section#break-in") { assert_text "Coming soon" }
    within("section#phishing") do
      assert_selector "[data-testid=path-progress]", text: "0 of 2 missions finished"
      click_on "Basics"
    end

    assert_selector "h1", text: "Basics"
    within("nav[aria-label=Breadcrumb]") { assert_link "Phishing", href: paths_path(anchor: "phishing") }
    first(:link, "Read the briefing").click
    click_on "Start mission"
    accept_confirm { click_on "Stand down" }
    assert_selector "[data-testid=debrief-ending]", text: /You stood down/

    visit paths_path
    within("section#phishing") { assert_selector "[data-testid=path-progress]", text: "1 of 2 missions finished" }
  end
end
