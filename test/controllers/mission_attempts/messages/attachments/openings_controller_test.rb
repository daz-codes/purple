require "test_helper"

class MissionAttempts::Messages::Attachments::OpeningsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @attempt = MissionAttempt.start(user: users(:one), mission: missions(:month_end))
    sign_in_as users(:one)
  end

  test "opening a document shows a preview" do
    post mission_attempt_message_attachment_opening_path(@attempt, @attempt.message_ref(messages(:real_invoice)), "a1"), as: :turbo_stream

    assert_response :success
    assert_select "turbo-stream[target=mission_browser] template dialog", text: /Invoice_4471\.pdf/
    assert_equal "file_preview", @attempt.reload.current_tab.landing
  end
end
