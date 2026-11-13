require "application_system_test_case"

# Plays the fixture message shift on the phone: Sam's text (needs a reply) at the start; the fake "IT
# Support" chat, asking for a one-time code, once one message has been dealt with.
class MessageShiftTest < ApplicationSystemTestCase
  setup do
    sign_in users(:one)
    visit shift_path(shifts(:site_visit))
    click_on "Start shift"
  end

  test "reply to a colleague, check with the service desk, report the fake IT chat, and see it all in the debrief" do
    within("#shift_inbox") { click_on "Sam (Ops)" }
    assert_selector "#shift_inbox", visible: :hidden # one screen at a time
    within("#shift_reader") do
      assert_selector "h2", text: "Sam (Ops)"
      click_on "Sure, see you there"
      assert_selector "[data-testid=reply-response]", text: "Legend, thanks!"
      click_on "Archive"
    end
    assert_text "1 new message arrived."
    assert_no_answers

    within("#shift_inbox") { click_on "IT Support (Larkhill)" }
    within("#shift_reader") do
      assert_selector "h2", text: "IT Support (Larkhill)"
      assert_text "it.support.larkhill@freemail.test"
      assert_text "Workchat"
      assert_selector "[aria-label='Reply with'] button", count: 3

      click_on "I'll check with the service desk first."
      assert_selector "[data-testid=sent-reply]", text: "I'll check with the service desk first."
      assert_selector "[data-testid=reply-check]", text: "The IT service desk says that isn't them."
      click_on "Report phishing"
    end

    # That was the last message: the shift ends by itself.
    assert_selector "[data-testid=debrief-ending]", text: /You cleared your phone in/
    chat = all("[data-testid=debrief-message]").find { |card| card.has_text?("IT Support (Larkhill)") }
    within(chat) do
      assert_selector "[data-testid=debrief-verdict]", text: "Phish: reported"
      assert_text "You replied “I'll check with the service desk first.”, and gave them nothing they could use."
      assert_text "You checked with someone you already trust"
    end
    sam = all("[data-testid=debrief-message]").find { |card| card.has_text?("Sam (Ops)") }
    within(sam) { assert_selector "[data-testid=debrief-verdict]", text: "Genuine: dealt with" }
  end

  test "handing over the code says nothing until the debrief" do
    within("#shift_inbox") { click_on "Sam (Ops)" }
    within("#shift_reader") { click_on "Archive" }
    within("#shift_inbox") { click_on "IT Support (Larkhill)" }
    within("#shift_reader") do
      click_on "Here it is: 482 913"
      assert_selector "[data-testid=reply-response]", text: "Thanks, you're all locked down now."
    end
    assert_no_selector "[role=alert]"
    assert_no_text "signed in to your account"
  end
end
