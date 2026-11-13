require "test_helper"

class ShiftAttempts::Messages::ReadingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @attempt = ShiftAttempt.start(user: users(:one), shift: shifts(:month_end))
    sign_in_as users(:one)
  end

  test "reading a message updates the panes with Turbo Streams" do
    post shift_attempt_message_reading_path(@attempt, ref(:real_invoice)), as: :turbo_stream

    assert_response :success
    assert_equal messages(:real_invoice), @attempt.reload.current_message
    %w[ shift_status shift_inbox shift_reader ].each do |target|
      assert_select "turbo-stream[action=replace][target=#{target}]"
    end
  end

  test "without Turbo the player is sent back to the play screen" do
    post shift_attempt_message_reading_path(@attempt, ref(:real_invoice))

    assert_redirected_to shift_attempt_path(@attempt)
  end

  test "a message that hasn't arrived is refused, and nothing changes" do
    post shift_attempt_message_reading_path(@attempt, ref(:fake_invoice)), as: :turbo_stream

    assert_response :unprocessable_content
    assert_select "turbo-stream[target=shift_notice] template", text: "That message isn't in your inbox."
    assert_empty @attempt.attempt_actions
  end

  test "a message's key or a made-up ref is refused" do
    [ "real_invoice", "m1" ].each do |guess|
      post shift_attempt_message_reading_path(@attempt, guess), as: :turbo_stream
      assert_response :unprocessable_content
    end
    assert_empty @attempt.attempt_actions
  end

  test "players can't act on someone else's attempt" do
    sign_in_as users(:two)
    post shift_attempt_message_reading_path(@attempt, ref(:real_invoice))

    assert_response :not_found
    assert_empty @attempt.attempt_actions
  end

  private
    def ref(message)
      @attempt.message_ref(messages(message))
    end
end
