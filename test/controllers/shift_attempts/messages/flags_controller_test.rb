require "test_helper"

class ShiftAttempts::Messages::FlagsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @attempt = ShiftAttempt.start(user: users(:one), shift: shifts(:month_end))
    @attempt.wait_for_mail
    @attempt.read(messages(:fake_invoice))
    @ref = @attempt.message_ref(messages(:fake_invoice))
    sign_in_as users(:one)
  end

  test "flagging a part keeps the reader in flag mode and doesn't say whether it was right" do
    post shift_attempt_message_flags_path(@attempt, @ref), params: { anchor: "from" }, as: :turbo_stream

    assert_response :success
    assert_equal %w[ from ], @attempt.reload.flagged_anchors(messages(:fake_invoice))
    assert_select "turbo-stream[target=shift_reader] template" do
      assert_select "[data-flag-mode-active-value=true]"
      assert_select "[data-testid=your-flags]", text: /the sender/
    end
    assert_not_includes response.body, "Lookalike"
  end

  test "an anchor the message doesn't have is refused" do
    post shift_attempt_message_flags_path(@attempt, @ref), params: { anchor: "p9" }, as: :turbo_stream

    assert_response :unprocessable_content
  end
end
