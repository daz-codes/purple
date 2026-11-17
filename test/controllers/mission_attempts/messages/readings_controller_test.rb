require "test_helper"

class MissionAttempts::Messages::ReadingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @attempt = MissionAttempt.start(user: users(:one), mission: missions(:month_end))
    sign_in_as users(:one)
  end

  test "reading a message updates the panes with Turbo Streams" do
    post mission_attempt_message_reading_path(@attempt, ref(:real_invoice)), as: :turbo_stream

    assert_response :success
    assert_equal messages(:real_invoice), @attempt.reload.current_message
    %w[ mission_status mission_inbox mission_reader ].each do |target|
      assert_select "turbo-stream[action=replace][target=#{target}]"
    end
  end

  test "without Turbo the player is sent back to the play screen" do
    post mission_attempt_message_reading_path(@attempt, ref(:real_invoice))

    assert_redirected_to mission_attempt_path(@attempt)
  end

  test "a message that hasn't arrived is refused, and nothing changes" do
    post mission_attempt_message_reading_path(@attempt, ref(:fake_invoice)), as: :turbo_stream

    assert_response :unprocessable_content
    assert_select "turbo-stream[target=mission_notice] template", text: "That message isn't in your inbox."
    assert_empty @attempt.attempt_actions
  end

  test "a message's key or a made-up ref is refused" do
    [ "real_invoice", "m1" ].each do |guess|
      post mission_attempt_message_reading_path(@attempt, guess), as: :turbo_stream
      assert_response :unprocessable_content
    end
    assert_empty @attempt.attempt_actions
  end

  test "players can't act on someone else's attempt" do
    sign_in_as users(:two)
    post mission_attempt_message_reading_path(@attempt, ref(:real_invoice))

    assert_response :not_found
    assert_empty @attempt.attempt_actions
  end

  private
    def ref(message)
      @attempt.message_ref(messages(message))
    end
end
