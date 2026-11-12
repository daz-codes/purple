require "application_system_test_case"

# Plays the fixture shift: a legitimate invoice (m1) at minute 0 and a phish (m2) at minute 3.
class ShiftPlayTest < ApplicationSystemTestCase
  test "report the phish, leave the legitimate email alone and end the shift" do
    sign_in users(:one)

    visit shift_path(shifts(:month_end))
    assert_text "It's month-end."
    click_on "Start shift"

    assert_selector "[data-testid=clock]", text: "Minute 0 of 30"
    within("#shift_tasks") { assert_text "Approve invoice" }
    within("#shift_inbox") { assert_text "Invoice ready" }
    assert_no_text "URGENT invoice"
    assert_no_answers

    # Read the legitimate invoice and leave it alone. Hovering a link shows where it really goes.
    within("#shift_inbox") { click_on "Invoice ready" }
    within("#shift_reader") do
      assert_selector "h2", text: "Invoice ready"
      find(".fake-link", text: "Review").hover
      assert_text "https://portal.larkhill.example/invoices/4471"
    end
    assert_no_answers

    # Time passes and the phish arrives.
    click_on "Wait for new mail (3 min)"
    assert_text "1 new message arrived."
    assert_selector "[data-testid=clock]", text: "Minute 3 of 30"
    within("#shift_inbox") { click_on "URGENT invoice" }

    # Check it: the full headers show the real addresses, and the sender's call-back answer appears.
    within("#shift_reader") do
      # Wait for the reader to show the phish, or the click could land on the previous message's button.
      assert_selector "h2", text: "URGENT invoice"
      assert_no_text "accounts@tidemark-billing.example"
      click_on "Show full headers (1 min)"
      assert_text "accounts@tidemark-billing.example"
      assert_text "nw.payments@freemail.test"

      click_on "Call the sender back (5 min)"
      assert_selector "[data-testid=verify-result]", text: "Tidemark haven't changed their bank details."
    end
    assert_selector "[data-testid=clock]", text: "Minute 9 of 30"
    assert_no_answers

    within("#shift_reader") { click_on "Report phishing (1 min)" }
    within("#shift_inbox") do
      assert_text "Reported (1)"
      assert_no_button "URGENT invoice"
    end
    assert_selector "[data-testid=clock]", text: "Minute 10 of 30"
    # The meter doesn't reveal whether the report was right.
    assert_selector "[data-testid=security]", text: "100%"
    assert_no_answers

    accept_confirm { click_on "End shift" }

    assert_selector "h1", text: "Month-end"
    assert_text "You ended your shift at minute 10 of 30."
    assert_selector "[data-testid=security-score]", text: "30"
    assert_selector "[data-testid=productivity-score]", text: "-20"
    assert_selector "[data-testid=score]", text: "10"
    assert_text "out of 80"
    assert ShiftAttempt.sole.completed?
  end
end
