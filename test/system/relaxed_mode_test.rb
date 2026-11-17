require "application_system_test_case"

class RelaxedModeTest < ApplicationSystemTestCase
  test "turn on relaxed mode: the mission says so, and the debrief has no timing" do
    sign_in users(:one)
    find("[data-testid=current-user]").click
    check "Relaxed mode"
    click_on "Save settings"
    assert_text "Settings saved."

    visit mission_path(missions(:site_visit))
    assert_text "You're in relaxed mode"
    click_on "Start mission"
    assert_selector "#mission_status", text: /relaxed mode/i

    accept_confirm { click_on "Stand down" }
    assert_selector "[data-testid=speed-bonus]", text: "0"
    assert_text "Not timed: you played in relaxed mode."
  end
end
