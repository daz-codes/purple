require "test_helper"

class ShiftAttempts::Messages::ReportsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @attempt = ShiftAttempt.start(user: users(:one), shift: shifts(:month_end))
    @attempt.archive(messages(:newsletter))
    sign_in_as users(:one)
  end

  test "reporting moves the message out of the inbox" do
    post shift_attempt_message_report_path(@attempt, @attempt.message_ref(messages(:fake_invoice))), as: :turbo_stream

    assert_response :success
    assert @attempt.reload.reported?(messages(:fake_invoice))
    assert_select "turbo-stream[target=shift_inbox] template", text: /Reported \(1\)/
  end
end
