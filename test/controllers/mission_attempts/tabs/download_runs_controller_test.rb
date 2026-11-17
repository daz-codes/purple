require "test_helper"

class MissionAttempts::Tabs::DownloadRunsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @attempt = MissionAttempt.start(user: users(:one), mission: missions(:month_end))
    @attempt.archive(messages(:newsletter))
    sign_in_as users(:one)
  end

  test "running a disguised attachment closes it, and nothing says it went wrong" do
    @attempt.open_attachment(messages(:fake_invoice), "a1")
    post mission_attempt_tab_download_run_path(@attempt), as: :turbo_stream

    assert_response :success
    assert_select "[role=alert]", count: 0
    assert_select "turbo-stream[target=mission_browser] template dialog", count: 0
    assert @attempt.reload.scorecard.message_result_for("fake_invoice").compromised?
  end
end
