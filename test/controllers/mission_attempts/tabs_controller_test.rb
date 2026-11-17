require "test_helper"

class MissionAttempts::TabsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @attempt = MissionAttempt.start(user: users(:one), mission: missions(:month_end))
    sign_in_as users(:one)
  end

  test "closing the tab empties the browser" do
    @attempt.visit(links(:real_invoice_link))
    delete mission_attempt_tab_path(@attempt), as: :turbo_stream

    assert_response :success
    assert_nil @attempt.reload.current_tab
    assert_select "turbo-stream[target=mission_browser] template dialog", count: 0
  end
end
