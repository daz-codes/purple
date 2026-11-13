require "application_system_test_case"

# The in-game browser on the fixture month-end shift. The fake invoice (a lookalike sign-in link and a
# .pdf.exe) arrives once the newsletter has been archived.
class ShiftBrowserTest < ApplicationSystemTestCase
  setup do
    sign_in users(:one)
    visit shift_path(shifts(:month_end))
    click_on "Start shift"
    within("#shift_inbox") { click_on "This week at Larkhill" }
    within("#shift_reader") do
      assert_selector "h2", text: "This week at Larkhill"
      click_on "Archive"
    end
    within("#shift_inbox") { click_on "URGENT invoice" }
    within("#shift_reader") { assert_selector "h2", text: "URGENT invoice" }
  end

  test "a near miss: open the lookalike sign-in page, read the address bar and close the tab" do
    within("#shift_reader") { find(".fake-link", text: "Pay now").click }

    within("dialog") do
      assert_selector "[data-testid=address-bar]", text: "https://larkhill-portal.example.net/login"
      assert_selector "input[placeholder='Never enter a real password']"
      assert_no_answers
      click_on "Close tab"
    end
    assert_no_selector "dialog"
  end

  test "signing in on the lookalike page looks just like a real portal: a plain confirmation, and no alarm" do
    within("#shift_reader") { find(".fake-link", text: "Pay now").click }

    within("dialog") do
      fill_in "Password on this page", with: "not-a-real-password"
      click_on "Sign in"
      assert_text "that's been submitted"
    end
    assert_no_selector "[role=alert]"
    assert_not_includes ShiftAttempt.sole.attempt_actions.to_json, "not-a-real-password"
    assert_no_answers

    within("dialog") { click_on "Close tab" }
    within("#shift_reader") { click_on "Report phishing" }
    within("#shift_inbox") { assert_text "Reported (1)" }
  end

  test "a disguised attachment asks before it runs, and running it just closes it" do
    within("#shift_reader") { click_on "Open attachment Remittance_4471.pdf.exe" }

    within("dialog") do
      assert_text "Open this file?"
      assert_no_answers
      click_on "Open file"
    end
    assert_no_selector "dialog"
    assert_no_selector "[role=alert]"
  end
end
