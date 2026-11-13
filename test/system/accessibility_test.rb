require "application_system_test_case"

# axe (WCAG 2.1 A and AA) on the key pages, signed out and signed in.
class AccessibilityTest < ApplicationSystemTestCase
  test "public pages" do
    { root_path => "Attack", new_session_path => "Sign in", new_registration_path => "Create", tracks_path => "Pick a track",
      track_path(tracks(:basics)) => "Month-end", shift_path(shifts(:month_end)) => "Briefing", targets_path => "Red's Workshop",
      target_path(targets(:month_end_target)) => "Recon", leaderboard_path => "Leaderboard", profile_path("blue_one") => "blue_one" }.each do |path, text|
      visit path
      assert_text(/#{Regexp.escape(text)}/i)
      assert_accessible
    end
  end

  test "a player's pages: dashboard, account, a shift, its debrief, and a Workshop campaign" do
    sign_in users(:one)
    assert_accessible

    visit account_path
    assert_accessible

    visit shift_path(shifts(:month_end))
    click_on "Start shift"
    within("#shift_inbox") { click_on "Invoice ready" }
    assert_selector "#shift_reader h2", text: "Invoice ready"
    assert_accessible
    accept_confirm { click_on "Clock off early" }
    assert_selector "h2", text: "Message by message"
    assert_accessible

    visit target_path(targets(:month_end_target))
    click_on "Start a campaign"
    assert_selector "[data-testid=slot-pretext]"
    assert_accessible
  end

  test "a shift can be played with the keyboard alone" do
    sign_in users(:one)
    visit shift_path(shifts(:month_end))
    find("button", text: "Start shift").send_keys(:enter)

    find("#shift_inbox button", text: "Invoice ready").send_keys(:enter)
    assert_selector "#shift_reader h2", text: "Invoice ready"

    # A link in the message is a focusable span that opens with Enter.
    find("#shift_reader .fake-link", text: "Review").send_keys(:enter)
    within("dialog") do
      find("button", text: "Approve invoice").send_keys(:enter)
      assert_text "that's been submitted"
      find("button", text: "Close tab").send_keys(:enter)
    end
    assert_no_selector "dialog"

    find("#shift_reader button", text: "Archive").send_keys(:enter)
    within("#shift_inbox") { assert_text "Done (1)" }
  end

  test "the phone" do
    sign_in users(:one)
    visit shift_path(shifts(:site_visit))
    click_on "Start shift"
    within("#shift_inbox") { click_on "Sam (Ops)" }
    assert_selector "#shift_reader h2", text: "Sam (Ops)"

    assert_accessible
  end
end
