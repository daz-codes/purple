require "application_system_test_case"

class RelaxedModeTest < ApplicationSystemTestCase
  test "turn on relaxed mode: the shift says so, and the debrief has no timing" do
    sign_in users(:one)
    click_on "Settings"
    check "Relaxed mode"
    click_on "Save settings"
    assert_text "Settings saved."

    visit shift_path(shifts(:site_visit))
    assert_text "You're in relaxed mode"
    click_on "Start shift"
    assert_selector "#shift_status", text: /relaxed mode/i

    accept_confirm { click_on "Clock off early" }
    assert_selector "[data-testid=speed-bonus]", text: "0"
    assert_text "Not timed: you played in relaxed mode."
  end
end
