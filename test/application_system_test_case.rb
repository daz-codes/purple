require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1000 ]

  # Let tests find buttons and links by their aria-label, as screen reader users would.
  Capybara.enable_aria_label = true
  # The first page of a run (compiling assets, warming Puma) can take longer than the default 2 seconds.
  Capybara.default_max_wait_time = 5

  # Things only the server may know until the debrief: answer words, the fixtures' descriptive keys,
  # technique tags and red-flag labels. None may appear anywhere in a mid-shift page.
  SHIFT_SECRETS = %w[
    legit outcome expects arrives_after bait_landing credential_harvest malware harmless file_preview
    real_invoice fake_invoice newsletter supplier_thanks sam_text it_chat lookalike_domain T1583 lookalike
    pay_today code_request compromise
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
