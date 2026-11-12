require "application_system_test_case"

# Plays the fixture message shift on the phone: a genuine text from Sam at minute 0, and a fake "IT
# Support" chat at minute 2 that asks for a one-time code.
class MessageShiftTest < ApplicationSystemTestCase
  setup do
    sign_in users(:one)
    visit shift_path(shifts(:site_visit))
    click_on "Start shift"
  end

  test "check with the service desk, report the fake IT chat, reply to a colleague and see it all in the debrief" do
    within("#shift_inbox") { assert_text "Sam (Ops)" }
    assert_no_text "IT Support (Larkhill)"
    click_on "Wait for new messages (2 min)"
    assert_text "1 new message arrived."

    within("#shift_inbox") { click_on "IT Support (Larkhill)" }
    assert_selector "#shift_inbox", visible: :hidden # one screen at a time
    within("#shift_reader") do
      assert_selector "h2", text: "IT Support (Larkhill)"
      assert_text "it.support.larkhill@freemail.test" # no headers to expand on a phone
      assert_text "Workchat"
      assert_selector "[aria-label='Reply with'] button", count: 3
    end
    assert_no_answers

    within("#shift_reader") do
      click_on "🚩 Flag red flags"
      find("[data-anchor=p2]").click
      assert_selector "[data-testid=your-flags]", text: "paragraph 2"

      click_on "I'll check with the service desk first. (1 min)"
      assert_selector "[data-testid=sent-reply]", text: "I'll check with the service desk first."
      assert_selector "[data-testid=verify-result]", text: "The IT service desk says that isn't them."
      assert_no_selector "[aria-label='Reply with']"
    end
    assert_selector "[data-testid=clock]", text: "Minute 8 of 30" # 2 + 1 for the reply + 5 for the check
    assert_no_answers

    within("#shift_reader") { click_on "Report phishing (1 min)" }
    within("#shift_reader") { click_on "Back to all messages" }
    within("#shift_inbox") do
      assert_text "Reported (1)"
      click_on "Sam (Ops)"
    end
    within("#shift_reader") do
      assert_selector "h2", text: "Sam (Ops)"
      click_on "Sure, see you there (1 min)"
      assert_selector "[data-testid=reply-response]", text: "Legend, thanks!"
    end
    assert_selector "[data-testid=security]", text: "100%"

    accept_confirm { click_on "End shift" }

    chat = all("[data-testid=debrief-message]").find { |card| card.has_text?("IT Support (Larkhill)") }
    within(chat) do
      assert_selector "[data-testid=debrief-verdict]", text: "Phish"
      assert_text "Workchat from IT Support (Larkhill)"
      assert_text "You replied “I'll check with the service desk first.”, and gave them nothing they could use."
      assert_text "You checked with someone you already trust"
      assert_selector "[data-testid=debrief-red-flags]", text: "Flagged +15 Asks for a one-time code."
    end
  end

  test "handing over the code shows the damage at once" do
    click_on "Wait for new messages (2 min)"
    within("#shift_inbox") { click_on "IT Support (Larkhill)" }
    within("#shift_reader") { click_on "Here it is: 482 913 (1 min)" }

    assert_text "someone signed in to your account from abroad"
    assert_selector "[data-testid=security]", text: "50%"
    within("#shift_reader") { assert_selector "[data-testid=reply-response]", text: "Thanks, you're all locked down now." }
  end
end
