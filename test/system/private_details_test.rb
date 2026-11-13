require "application_system_test_case"

# Month-end, with private details: the real invoice's portal needs your staff number, the fake
# invoice's lookalike page wants it, and the newsletter mentions something worth noting. Then the site
# visit, where the fake IT chat can be asked why it wants things.
class PrivateDetailsTest < ApplicationSystemTestCase
  test "save a note, give the portal what it needs, give a phish your staff number, and see what Red now knows" do
    newsletter = messages(:newsletter)
    start = newsletter.paragraphs["p1"].text.index("new menu")
    newsletter.update!(details: [ { "key" => "canteen_menu", "label" => "The new menu", "sensitivity" => "internal", "anchor" => "p1",
                                    "quote" => "new menu", "quote_start" => start, "quote_end" => start + 8 } ])
    messages(:real_invoice).update!(needs: %w[ staff_number ])
    messages(:fake_invoice).update!(wants: %w[ staff_number ])

    sign_in users(:one)
    visit shift_path(shifts(:month_end))
    click_on "Start shift"
    assert_selector "[data-testid=persona-card]"
    staff_number = users(:one).shift_attempts.open.sole.persona.staff_number
    within("[data-testid=authenticator]") { assert_text "No sign-in requests" }

    # A note: words saved from a message, ready to send later.
    within("#shift_inbox") { click_on "This week at Larkhill" }
    within("#shift_reader") do
      click_on "📝 Save to notes"
      find("[data-anchor=p1s1]").click
      assert_selector "[data-testid=your-notes]", text: "The canteen has a new menu."
      click_on "Archive"
    end
    within("[data-testid=notes-list]") { assert_text "The canteen has a new menu." }
    assert_no_answers

    # The real portal asks for the staff number in a field filled by picking a chip.
    within("#shift_inbox") { click_on "Invoice ready" }
    within("#shift_reader") { find(".fake-link", text: "Review").click }
    within("dialog") do
      select "Staff number: #{staff_number}", from: "Staff number"
      click_on "Approve invoice"
      assert_text "that's been submitted"
      click_on "Close tab"
    end
    within("#shift_reader") { click_on "Archive" }
    assert_no_answers

    # The lookalike page wants it too, and gets it.
    within("#shift_inbox") { click_on "URGENT invoice" }
    within("#shift_reader") { find(".fake-link", text: "Pay now").click }
    within("dialog") do
      select "Staff number: #{staff_number}", from: "Staff number"
      click_on "Sign in"
      assert_text "that's been submitted"
      click_on "Close tab"
    end
    within("#shift_reader") { click_on "Report phishing" }
    assert_no_answers

    within("#shift_inbox") { click_on "Thanks for approving" }
    within("#shift_reader") { click_on "Archive" }

    assert_selector "[data-testid=red-knows]", text: "Your staff number (#{staff_number}): Red could quote it to HR or the service desk to pass as you."
    assert_selector "[data-testid=debrief-details]", text: "It got the staff number it needed, in the right place."
    assert_selector "[data-testid=debrief-details]", text: "You gave them your staff number. That's falling for it"
  end

  test "ask the fake IT chat why it wants your details, then refuse and report it" do
    shifts(:site_visit).update!(persona: shifts(:month_end).persona)
    messages(:it_chat).update!(wants: %w[ name ],
      replies: messages(:it_chat).replies + [ { "id" => "r4", "text" => "Why do you need this?", "outcome" => "ask_why",
                                                "response" => "No time to explain, just send it!" } ])

    sign_in users(:one)
    visit shift_path(shifts(:site_visit))
    click_on "Start shift"

    within("#shift_inbox") { click_on "Sam (Ops)" }
    within("#shift_reader") do
      click_on "Sure, see you there"
      click_on "Archive"
    end

    within("#shift_inbox") { click_on "IT Support (Larkhill)" }
    within("#shift_reader") do
      click_on "Why do you need this?"
      assert_selector "[data-testid=why-answer]", text: "No time to explain, just send it!"
      assert_no_button "Why do you need this?"
      assert_selector "[data-testid=details-box]"
      assert_no_answers
      click_on "I won't share a code."
      click_on "Report phishing"
    end
  end
end
