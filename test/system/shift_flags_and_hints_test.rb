require "application_system_test_case"

# Flag mode and hints on the fixture shift: the phish (arriving at minute 3) has one red flag, on its
# sender; the shift has one hint.
class ShiftFlagsAndHintsTest < ApplicationSystemTestCase
  test "flag the parts of a phish that look wrong, take a hint, and see both in the debrief" do
    sign_in users(:one)
    visit shift_path(shifts(:month_end))
    click_on "Start shift"
    click_on "Wait for new mail (3 min)"
    within("#shift_inbox") { click_on "URGENT invoice" }

    within("#shift_reader") do
      assert_selector "h2", text: "URGENT invoice"
      click_on "🚩 Flag red flags"
      assert_text "Flag mode."

      find("[data-anchor=from]").click
      assert_selector "[data-testid=your-flags]", text: "the sender"
      assert_selector "[data-anchor=from].flagged"

      # In flag mode a link is flagged, not visited.
      find(".fake-link", text: "Pay now").click
      assert_selector "[data-testid=your-flags]", text: "the sender and the link “Pay now”"
      find(".fake-link", text: "Pay now").click
      assert_selector "[data-testid=your-flags]", text: "the sender"
      assert_no_text "the link “Pay now”"
    end
    assert_no_selector "dialog[open]"
    assert_selector "[data-testid=clock]", text: "Minute 3 of 30" # flags are free
    assert_no_answers

    within("#shift_hints") do
      accept_confirm { click_on "Take a hint" }
      assert_selector "[data-testid=hints]", text: "Compare the sender domains."
      assert_text "That's every hint for this shift."
    end

    within("#shift_reader") { click_on "Report phishing (1 min)" }
    within("#shift_inbox") { assert_text "Reported (1)" }
    accept_confirm { click_on "End shift" }

    assert_selector "[data-testid=debrief-hints]", text: "Hints: −16"
    phish = all("[data-testid=debrief-message]").find { |card| card.has_text?("URGENT invoice") }
    within(phish) do
      assert_selector "[data-testid=debrief-red-flags]", text: "Flagged +10 Lookalike sender domain."
      assert_text "you flagged 1 of 1"
    end
    # -20 for the missed task, 30 + 10 for the phish, -16 for the hint.
    assert_selector "[data-testid=score]", text: "4"
  end
end
