require "application_system_test_case"

# Plays the fixture month-end shift to the end. At the start: the real invoice (needs approving on its
# portal) and a newsletter. The fake invoice arrives once one message is dealt with; the supplier's
# thank-you once the real invoice is.
class ShiftPlayTest < ApplicationSystemTestCase
  test "deal with every message: approve the invoice, archive what needs nothing, report the phish" do
    sign_in users(:one)
    visit shift_path(shifts(:month_end))
    assert_text "It's month-end."
    click_on "Start shift"

    # No task list, no clock, no meters: just the inbox.
    assert_selector "[data-testid=inbox-count]", text: "2 emails to deal with"
    assert_no_selector "[data-testid=clock]"
    assert_no_text "Productivity"
    within("#shift_inbox") { assert_text "Invoice ready" }
    assert_no_text "URGENT invoice"
    assert_no_answers

    # The newsletter needs nothing: archive it. That brings the next message.
    within("#shift_inbox") { click_on "This week at Larkhill" }
    within("#shift_reader") do
      assert_selector "h2", text: "This week at Larkhill"
      click_on "Archive"
    end
    assert_text "1 new message arrived."
    within("#shift_inbox") { assert_text "URGENT invoice" }
    within("#shift_inbox") { assert_text "Done (1)" }

    # The real invoice: approve it on its portal, then archive it.
    within("#shift_inbox") { click_on "Invoice ready" }
    within("#shift_reader") do
      assert_selector "h2", text: "Invoice ready"
      find(".fake-link", text: "Review").hover
      assert_text "https://portal.larkhill.example/invoices/4471"
      find(".fake-link", text: "Review").click
    end
    within("dialog") do
      assert_selector "[data-testid=address-bar]", text: "https://portal.larkhill.example/invoices/4471"
      click_on "Approve invoice"
      assert_text "that's been submitted"
      click_on "Close tab"
    end
    within("#shift_reader") { click_on "Archive" }
    within("#shift_inbox") { assert_text "Thanks for approving" }
    assert_no_answers

    # The phish: check it, then report it.
    within("#shift_inbox") { click_on "URGENT invoice" }
    within("#shift_reader") do
      assert_selector "h2", text: "URGENT invoice"
      assert_no_text "accounts@tidemark-billing.example"
      click_on "Show full headers"
      assert_text "accounts@tidemark-billing.example"
      assert_text "nw.payments@freemail.test"
      click_on "Call the sender back"
      assert_selector "[data-testid=verify-result]", text: "Tidemark haven't changed their bank details."
      click_on "Report phishing"
    end
    within("#shift_inbox") { assert_text "Reported (1)" }
    assert_no_answers

    # The last message: archiving it clears the inbox, and the shift ends by itself.
    within("#shift_inbox") { click_on "Thanks for approving" }
    within("#shift_reader") do
      assert_selector "h2", text: "Thanks for approving"
      click_on "Archive"
    end

    assert_selector "h1", text: "Month-end"
    assert_selector "[data-testid=debrief-ending]", text: /You cleared your inbox in .+\. The target was 10 minutes\./
    assert_selector "[data-testid=debrief-headline]",
      text: "You reported 1 of 1 phish, dealt with 3 of 3 genuine messages, and spotted 0 of 2 red flags."
  end
end
