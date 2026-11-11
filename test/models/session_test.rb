require "test_helper"

class SessionTest < ActiveSupport::TestCase
  test "describes common browsers and platforms" do
    chrome_mac = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36"
    safari_iphone = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    assert_equal "Chrome on macOS", Session.new(user_agent: chrome_mac).device_description
    assert_equal "Safari on iPhone", Session.new(user_agent: safari_iphone).device_description
  end

  test "falls back for unknown user agents" do
    assert_equal "Unknown device", Session.new(user_agent: nil).device_description
  end
end
