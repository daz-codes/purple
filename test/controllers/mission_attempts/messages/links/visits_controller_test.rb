require "test_helper"

class MissionAttempts::Messages::Links::VisitsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @attempt = MissionAttempt.start(user: users(:one), mission: missions(:month_end))
    @attempt.archive(messages(:newsletter))
    sign_in_as users(:one)
  end

  test "visiting a link opens the in-game browser at its real address" do
    post mission_attempt_message_link_visit_path(@attempt, ref(:fake_invoice), "l1"), as: :turbo_stream

    assert_response :success
    assert_select "turbo-stream[target=mission_browser] template dialog [data-testid=address-bar]",
      text: /larkhill-portal\.example\.net\/login/
  end

  test "a link key that isn't in the message is refused" do
    post mission_attempt_message_link_visit_path(@attempt, ref(:fake_invoice), "l9"), as: :turbo_stream

    assert_response :unprocessable_content
    assert_select "turbo-stream[target=mission_notice] template", text: "That link isn't in the message."
  end

  private
    def ref(message) = @attempt.message_ref(messages(message))
end
