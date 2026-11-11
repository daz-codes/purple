require "application_system_test_case"

class AuthenticationTest < ApplicationSystemTestCase
  include ActiveJob::TestHelper

  PASSWORD = "correct horse battery"
  NEW_PASSWORD = "purple team debrief"

  setup { ActionMailer::Base.deliveries.clear }

  test "sign up, confirm email, sign out, sign in and reset password" do
    # Sign up
    visit root_path
    click_on "Sign up"
    fill_in "Display name", with: "rookie_blue"
    fill_in "Email address", with: "rookie@example.com"
    fill_in "Password", with: PASSWORD
    fill_in "Confirm password", with: PASSWORD
    perform_enqueued_jobs do
      click_on "Create account"
      assert_text "Check your email to confirm"
    end

    assert_selector "[data-testid=current-user]", text: "rookie_blue"
    assert_text "Confirm your email address to start earning XP"

    # Confirm via the emailed link
    visit link_from_last_email
    click_on "Confirm my email address"
    assert_text "your email address is confirmed"
    assert_no_text "Confirm your email address to start earning XP"
    assert User.find_by!(email_address: "rookie@example.com").confirmed?

    # Sign out and back in
    click_on "Sign out"
    assert_selector "h1", text: "Sign in"
    sign_in_with "rookie@example.com", PASSWORD
    assert_selector "[data-testid=current-user]", text: "rookie_blue"

    # Forget the password and reset it
    click_on "Sign out"
    click_on "Forgot password?"
    assert_selector "h1", text: "Forgot your password?"
    fill_in "Email address", with: "rookie@example.com"
    perform_enqueued_jobs do
      click_on "Email reset instructions"
      assert_text "reset instructions sent"
    end

    visit link_from_last_email
    fill_in "New password", with: NEW_PASSWORD
    fill_in "Confirm new password", with: NEW_PASSWORD
    click_on "Save new password"
    assert_text "Password has been reset"

    sign_in_with "rookie@example.com", PASSWORD
    assert_text "Try another email address or password"

    sign_in_with "rookie@example.com", NEW_PASSWORD
    assert_selector "[data-testid=current-user]", text: "rookie_blue"
  end

  test "revoke another device from the devices page" do
    user = users(:one)
    user.sessions.create!(user_agent: "Mozilla/5.0 (X11; Linux x86_64) Firefox/131.0", ip_address: "192.0.2.10")

    visit new_session_path
    sign_in_with user.email_address, PASSWORD
    click_on "Devices"

    assert_text "Firefox on Linux"
    click_on "Sign out Firefox on Linux"
    assert_text "That device has been signed out"
    assert_no_text "Firefox on Linux"
  end

  private
    def sign_in_with(email, password)
      fill_in "Email address", with: email
      fill_in "Password", with: password
      click_button "Sign in"
    end

    def link_from_last_email
      mail = ActionMailer::Base.deliveries.last
      assert mail, "expected an email to have been sent"
      url = mail.text_part.body.to_s[%r{https?://\S+}]
      URI.parse(url).request_uri
    end
end
