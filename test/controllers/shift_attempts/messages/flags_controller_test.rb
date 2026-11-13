require "test_helper"

class ShiftAttempts::Messages::FlagsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @attempt = ShiftAttempt.start(user: users(:one), shift: shifts(:month_end))
    @attempt.archive(messages(:newsletter))
    @attempt.read(messages(:fake_invoice))
    @ref = @attempt.message_ref(messages(:fake_invoice))
    sign_in_as users(:one)
  end

  test "flagging a part keeps the reader in flag mode and doesn't say whether it was right" do
    post shift_attempt_message_flags_path(@attempt, @ref), params: { anchor: "from" }, as: :turbo_stream

    assert_response :success
    assert_equal [ ShiftAttempt::Flag.new(anchor: "from", from: nil, to: nil) ], @attempt.reload.flags_on(messages(:fake_invoice))
    assert_select "turbo-stream[target=shift_reader] template" do
      assert_select "[data-flag-mode-active-value=true]"
      assert_select "[data-testid=your-flags]", text: /the sender/
    end
    assert_not_includes response.body, "Lookalike"
  end

  test "highlighted words are flagged by paragraph and range, and named by the words themselves" do
    post shift_attempt_message_flags_path(@attempt, @ref), params: { anchor: "p1", from: "4", to: "16" }, as: :turbo_stream

    assert_response :success
    assert_select "turbo-stream[target=shift_reader] template [data-testid=your-flags]", text: /“se pay today”/
    assert_select "turbo-stream[target=shift_reader] template [data-flag-mode-flags-value]" do |readers|
      assert_equal [ { "anchor" => "p1", "from" => 4, "to" => 16 } ], JSON.parse(readers.first["data-flag-mode-flags-value"])
    end
    assert_not_includes response.body, "Rushed payment"
  end

  test "an anchor the message doesn't have is refused" do
    post shift_attempt_message_flags_path(@attempt, @ref), params: { anchor: "p9" }, as: :turbo_stream

    assert_response :unprocessable_content
  end
end
