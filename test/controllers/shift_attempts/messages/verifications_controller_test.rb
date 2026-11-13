require "test_helper"

class ShiftAttempts::Messages::VerificationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @attempt = ShiftAttempt.start(user: users(:one), shift: shifts(:month_end))
    sign_in_as users(:one)
  end

  test "calling the sender back shows their reply" do
    @attempt.read(messages(:real_invoice))
    post shift_attempt_message_verification_path(@attempt, @attempt.message_ref(messages(:real_invoice))), as: :turbo_stream

    assert_response :success
    assert_equal 30, @attempt.reload.penalty_seconds
    assert_select "turbo-stream[target=shift_reader] template [data-testid=verify-result]", text: /Tidemark confirm they sent it/
    assert_no_match(/30 s|seconds/, response.body)
  end

  test "calling twice is refused" do
    @attempt.verify_sender(messages(:real_invoice))
    post shift_attempt_message_verification_path(@attempt, @attempt.message_ref(messages(:real_invoice))), as: :turbo_stream

    assert_response :unprocessable_content
    assert_select "turbo-stream[target=shift_notice] template", text: "You've already checked with the sender."
  end
end
