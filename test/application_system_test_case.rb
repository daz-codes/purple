require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1000 ]

  # Let tests find buttons and links by their aria-label, as screen reader users would.
  Capybara.enable_aria_label = true

  # Things only the server may know until the debrief: answer words, the fixtures' descriptive keys,
  # technique tags and red-flag labels. None may appear anywhere in a mid-shift page.
  SHIFT_SECRETS = %w[
    legit outcome task_id completes_task bait_landing credential_harvest malware harmless portal_task
    file_preview real_invoice fake_invoice pay_supplier lookalike_domain T1583 lookalike sam_text it_chat code_request
  ].freeze

  private
    def sign_in(user, password: "correct horse battery")
      visit new_session_path
      fill_in "Email address", with: user.email_address
      fill_in "Password", with: password
      click_button "Sign in"
      assert_selector "[data-testid=current-user]"
    end

    def assert_no_answers
      html = page.html
      SHIFT_SECRETS.each { |secret| assert_not_includes html, secret, "the page leaks #{secret.inspect}" }
    end
end
