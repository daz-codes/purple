require "test_helper"

class MissionAttempts::HintsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @attempt = MissionAttempt.start(user: users(:one), mission: missions(:month_end))
    sign_in_as users(:one)
  end

  test "taking a hint reveals it" do
    post mission_attempt_hints_path(@attempt), as: :turbo_stream

    assert_response :success
    assert_select "turbo-stream[target=mission_hints] template", text: /Compare the sender domains/
    assert_equal 1, @attempt.reload.hints_used
  end

  test "when the hints run out, the move is refused" do
    @attempt.use_hint
    post mission_attempt_hints_path(@attempt), as: :turbo_stream

    assert_response :unprocessable_content
  end
end
