require "application_system_test_case"

# The Purple debrief on the fixture month-end shift.
class ShiftDebriefTest < ApplicationSystemTestCase
  test "the debrief explains each message: what it was, what it needed, what you did and what to do next time" do
    sign_in users(:one)
    visit shift_path(shifts(:month_end))
    click_on "Start shift"

    # Archive the real invoice without approving it, run the fake's attachment, then report it.
    within("#shift_inbox") { click_on "Invoice ready" }
    within("#shift_reader") do
      assert_selector "h2", text: "Invoice ready"
      click_on "Archive"
    end
    within("#shift_inbox") { click_on "URGENT invoice" }
    within("#shift_reader") { click_on "Open attachment Remittance_4471.pdf.exe" }
    within("dialog") { click_on "Open file" }
    assert_no_selector "dialog"
    within("#shift_reader") { click_on "Report phishing" }
    within("#shift_inbox") { assert_text "Reported (1)" }

    accept_confirm { click_on "Clock off early" }

    assert_selector "h2", text: "Message by message"
    assert_selector "[data-testid=debrief-ending]", text: /You clocked off after/
    # -20 for the unapproved invoice, -5 for the newsletter left in the inbox, 30 - 50 for the phish,
    # 5 for archiving the thank-you: -40, so 0.
    assert_selector "[data-testid=score]", text: "0"
    assert_text "out of 105"
    assert_selector "[data-testid=speed-bonus]", text: "0"
    assert_selector "[data-testid=stars]", text: "☆☆☆"

    cards = all("[data-testid=debrief-message]")
    within(cards.find { |card| card.has_text?("URGENT invoice") }) do
      assert_selector "[data-testid=debrief-verdict]", text: "Phish: you fell for it"
      assert_text "You opened Remittance_4471.pdf.exe. Nothing seemed to happen, but it wasn't a document"
      assert_text "You reported it afterwards"
      assert_text "one that ends in .exe is a program"
      assert_text "Lookalike domain"
    end
    within(cards.find { |card| card.has_text?("Invoice ready") }) do
      assert_selector "[data-testid=debrief-verdict]", text: "Genuine: not dealt with"
      assert_text "needed you to “Approve invoice” through its link, but you archived it without doing that (−20)"
    end
    within(cards.find { |card| card.has_text?("This week at Larkhill") }) do
      assert_text "it was still in your inbox when you stopped"
    end

    find("summary", text: "Your shift, move by move").click
    within("[data-testid=debrief-timeline]") do
      assert_text "Archived “Invoice ready”"
      assert_text "Ran Remittance_4471.pdf.exe: compromised"
      assert_text "Clocked off early"
    end
  end
end
