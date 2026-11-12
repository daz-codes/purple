require "application_system_test_case"

# The in-game browser, on the fixture shift: the legitimate invoice (with a PDF) at minute 0 holds the
# link for the only task; the phish (with a sign-in link and a .pdf.exe) arrives at minute 3.
class ShiftBrowserTest < ApplicationSystemTestCase
  setup do
    sign_in users(:one)
    visit shift_path(shifts(:month_end))
    click_on "Start shift"
  end

  test "complete a task through the legitimate link" do
    within("#shift_inbox") { click_on "Invoice ready" }
    within("#shift_reader") { find(".fake-link", text: "Review").click }

    within("dialog") do
      assert_selector "[data-testid=address-bar]", text: "https://portal.larkhill.example/invoices/4471"
      assert_no_answers
      click_on "Approve invoice (2 min)"
    end

    # It was the only task, so the shift ends on time.
    assert_text "You ended your shift at minute 2 of 30."
    assert_text "On time (+40)"
  end

  test "a near miss: open the lookalike sign-in page, read the address bar and close the tab" do
    open_phish
    within("#shift_reader") { find(".fake-link", text: "Pay now").click }

    within("dialog") do
      assert_selector "[data-testid=address-bar]", text: "https://larkhill-portal.example.net/login"
      assert_selector "input[placeholder='Never enter a real password']"
      assert_no_answers
      click_on "Close tab"
    end

    assert_no_selector "dialog"
    # Closing a trap doesn't move the meter: that would give the answer away.
    assert_selector "[data-testid=security]", text: "100%"
    assert_no_answers
  end

  test "a compromise: sign in on the lookalike page, see the damage and carry on" do
    open_phish
    within("#shift_reader") { find(".fake-link", text: "Pay now").click }

    within("dialog") do
      fill_in "Password on this page", with: "not-a-real-password"
      click_on "Sign in"
    end

    assert_selector "[role=alert]", text: "Your account just sent 400 emails"
    assert_no_selector "dialog"
    assert_selector "[data-testid=security]", text: "50%"
    assert_not_includes ShiftAttempt.sole.attempt_actions.to_json, "not-a-real-password"

    # The shift carries on.
    within("#shift_reader") { click_on "Report phishing (1 min)" }
    within("#shift_inbox") { assert_text "Reported (1)" }
  end

  test "a disguised attachment asks before it runs" do
    open_phish
    within("#shift_reader") { click_on "Open attachment Remittance_4471.pdf.exe" }

    within("dialog") do
      assert_text "Open this file?"
      assert_no_answers
      click_on "Cancel"
    end
    assert_no_selector "dialog"
    assert_selector "[data-testid=security]", text: "100%"
  end

  private
    def open_phish
      click_on "Wait for new mail (3 min)"
      within("#shift_inbox") { click_on "URGENT invoice" }
      within("#shift_reader") { assert_selector "h2", text: "URGENT invoice" }
    end
end
