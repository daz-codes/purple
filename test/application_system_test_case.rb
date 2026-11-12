require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1000 ]

  # Let tests find buttons and links by their aria-label, as screen reader users would.
  Capybara.enable_aria_label = true
end
