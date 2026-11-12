require "test_helper"

class ShiftAttempts::Messages::Attachments::OpeningsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @attempt = ShiftAttempt.start(user: users(:one), shift: shifts(:month_end))
    sign_in_as users(:one)
  end

  test "opening a document shows a preview" do
    post shift_attempt_message_attachment_opening_path(@attempt, @attempt.message_ref(messages(:real_invoice)), "a1"), as: :turbo_stream

    assert_response :success
    assert_select "turbo-stream[target=shift_browser] template dialog", text: /Invoice_4471\.pdf/
    assert_equal "file_preview", @attempt.reload.current_tab.landing
  end
end
