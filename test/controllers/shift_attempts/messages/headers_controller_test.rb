require "test_helper"

class ShiftAttempts::Messages::HeadersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @attempt = ShiftAttempt.start(user: users(:one), shift: shifts(:month_end))
    sign_in_as users(:one)
  end

  test "showing full headers costs a minute" do
    post shift_attempt_message_headers_path(@attempt, @attempt.message_ref(messages(:real_invoice))), as: :turbo_stream

    assert_response :success
    assert_equal 1, @attempt.reload.clock_minutes
    assert @attempt.headers_expanded?(messages(:real_invoice))
  end

  test "a move that ends the shift goes to the results" do
    @attempt.update!(clock_minutes: 29)
    post shift_attempt_message_headers_path(@attempt, @attempt.message_ref(messages(:real_invoice))), as: :turbo_stream

    assert_redirected_to shift_attempt_path(@attempt)
    assert @attempt.reload.timed_out?
  end
end
