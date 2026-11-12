require "test_helper"

class ShiftAttempts::Tabs::DownloadRunsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @attempt = ShiftAttempt.start(user: users(:one), shift: shifts(:month_end))
    @attempt.wait_for_mail
    sign_in_as users(:one)
  end

  test "running a disguised attachment compromises the player" do
    @attempt.open_attachment(messages(:fake_invoice), "a1")
    post shift_attempt_tab_download_run_path(@attempt), as: :turbo_stream

    assert_select "turbo-stream[target=shift_notice] template [role=alert]", text: /being encrypted/
    assert_equal 50, @attempt.reload.scorecard.security_meter
  end
end
