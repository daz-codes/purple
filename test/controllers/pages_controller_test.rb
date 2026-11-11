require "test_helper"

class PagesControllerTest < ActionDispatch::IntegrationTest
  test "home page renders" do
    get root_path
    assert_response :success
    assert_select "h1", /Attack\. Defend\./
  end

  test "sends a strict content security policy" do
    get root_path
    csp = response.headers["Content-Security-Policy"]

    assert_includes csp, "frame-ancestors 'none'"
    assert_includes csp, "object-src 'none'"
    assert_match(/script-src 'self' 'nonce-[^']+'/, csp)
    assert_no_match(/unsafe-inline|unsafe-eval/, csp)
  end
end
