require "test_helper"

class SessionTest < ActiveSupport::TestCase
  test "describes common browsers and platforms" do
    chrome_mac = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36"
    safari_iphone = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    assert_equal "Chrome on macOS", Session.new(user_agent: chrome_mac).device_description
    assert_equal "Safari on iPhone", Session.new(user_agent: safari_iphone).device_description
  end

  test "names browsers that also mention Chrome or Safari in their user agent" do
    chrome_iphone = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/130.0 Mobile/15E148 Safari/604.1"
    firefox_iphone = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) FxiOS/132.0 Mobile/15E148 Safari/605.1.15"
    opera_windows = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36 OPR/115.0"
    edge_android = "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Mobile Safari/537.36 EdgA/130.0"

    assert_equal "Chrome on iPhone", Session.new(user_agent: chrome_iphone).device_description
    assert_equal "Firefox on iPhone", Session.new(user_agent: firefox_iphone).device_description
    assert_equal "Opera on Windows", Session.new(user_agent: opera_windows).device_description
    assert_equal "Edge on Android", Session.new(user_agent: edge_android).device_description
  end

  test "active excludes idle and very old sessions" do
    user = users(:one)
    fresh = user.sessions.create!
    idle = user.sessions.create!(updated_at: (Session::IDLE_TIMEOUT + 1.day).ago)
    old = user.sessions.create!(created_at: (Session::ABSOLUTE_TIMEOUT + 1.day).ago)

    assert_includes Session.active, fresh
    assert_not_includes Session.active, idle
    assert_not_includes Session.active, old
    assert_equal [ idle, old ].sort_by(&:id), Session.expired.where(user: user).sort_by(&:id)
  end

  test "record_activity touches the session at most once per granularity window" do
    session = users(:one).sessions.create!(updated_at: 2.hours.ago)
    session.record_activity
    assert_in_delta Time.current, session.reload.updated_at, 5.seconds

    assert_no_changes -> { session.reload.updated_at } do
      session.record_activity
    end
  end

  test "falls back for unknown user agents" do
    assert_equal "Unknown device", Session.new(user_agent: nil).device_description
  end
end
