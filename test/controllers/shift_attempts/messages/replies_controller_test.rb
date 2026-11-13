require "test_helper"

class ShiftAttempts::Messages::RepliesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @attempt = ShiftAttempt.start(user: users(:one), shift: shifts(:site_visit))
    @attempt.archive(messages(:sam_text)) # brings the IT chat
    @attempt.read(messages(:it_chat))
    @ref = @attempt.message_ref(messages(:it_chat))
    sign_in_as users(:one)
  end

  test "the phone offers each reply's text, never what it leads to" do
    get shift_attempt_path(@attempt)

    assert_response :success
    assert_select "[aria-label='Reply with'] button", text: "Here it is: 482 913"
    assert_select "input[name=reply][value=r1]"
    assert_no_match(/compromise|"safe"|"verify"|it_chat|Thanks, you're all locked down/, response.body)
  end

  test "a reply shows what was said and what came back, and nothing else" do
    post shift_attempt_message_reply_path(@attempt, @ref), params: { reply: "r1" }, as: :turbo_stream

    assert_response :success
    assert_select "turbo-stream[target=shift_reader] template" do
      assert_select "[data-testid=sent-reply]", text: "Here it is: 482 913"
      assert_select "[data-testid=reply-response]", text: "Thanks, you're all locked down now."
      assert_select "[aria-label='Reply with']", count: 0
    end
    assert_select "[role=alert]", count: 0
  end

  test "a reply the message doesn't offer is refused" do
    post shift_attempt_message_reply_path(@attempt, @ref), params: { reply: "r7" }, as: :turbo_stream

    assert_response :unprocessable_content
    assert_not @attempt.reload.replied?(messages(:it_chat))
  end
end
