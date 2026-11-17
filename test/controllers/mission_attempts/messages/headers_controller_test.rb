require "test_helper"

class MissionAttempts::Messages::HeadersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @attempt = MissionAttempt.start(user: users(:one), mission: missions(:month_end))
    sign_in_as users(:one)
  end

  test "showing full headers is free" do
    post mission_attempt_message_headers_path(@attempt, @attempt.message_ref(messages(:real_invoice))), as: :turbo_stream

    assert_response :success
    assert_equal 0, @attempt.reload.penalty_seconds
    assert @attempt.headers_expanded?(messages(:real_invoice))
  end

  test "an attempt left open too long is closed on the next move, which goes to the debrief" do
    travel MissionAttempt::Timed::EXPIRES_AFTER + 1.second
    post mission_attempt_message_headers_path(@attempt, @attempt.message_ref(messages(:real_invoice))), as: :turbo_stream

    assert_redirected_to mission_attempt_path(@attempt)
    assert @attempt.reload.timed_out?
  end
end
