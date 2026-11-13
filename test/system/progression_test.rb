require "application_system_test_case"

class ProgressionTest < ApplicationSystemTestCase
  test "a new player picks a side to try first" do
    visit new_registration_path
    fill_in "Email address", with: "fresh@example.com"
    fill_in "Display name", with: "fresh_face"
    fill_in "Password", with: "correct horse battery"
    fill_in "Confirm password", with: "correct horse battery"
    click_on "Create account"

    assert_selector "h1", text: "Which side do you want to try first?"
    click_on "Attack"
    assert_text "You're on the Red team. Pick a target."
    assert_equal "red", User.find_by!(email_address: "fresh@example.com").preferred_side
  end

  test "finishing a shift earns XP and a badge, and the dashboard shows them" do
    ActiveJob::Base.queue_adapter.perform_enqueued_jobs = true
    sign_in users(:one)
    visit shift_path(shifts(:month_end))
    click_on "Start shift"
    within("#shift_inbox") { click_on "This week at Larkhill" }
    within("#shift_reader") do
      assert_selector "h2", text: "This week at Larkhill"
      click_on "Archive"
    end
    within("#shift_inbox") { click_on "URGENT invoice" }
    within("#shift_reader") do
      assert_selector "h2", text: "URGENT invoice"
      click_on "Report phishing"
    end
    accept_confirm { click_on "Clock off early" }

    assert_selector "[data-testid=xp-earned]"
    score = ShiftAttempt.sole.score
    within("[data-testid=xp-earned]") do
      assert_text "+#{score} XP for the shift" if score.positive?
      assert_text "+10 XP first play today"
    end

    visit root_path
    assert_selector "[data-testid=streak]", text: "1 day in a row"
    within("[data-testid=badges]") { assert_selector "li[data-earned=true]", text: "First Catch" }
  ensure
    ActiveJob::Base.queue_adapter.perform_enqueued_jobs = false
  end
end
