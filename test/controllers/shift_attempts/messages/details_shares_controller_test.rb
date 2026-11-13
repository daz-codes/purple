require "test_helper"

class ShiftAttempts::Messages::DetailsSharesControllerTest < ActionDispatch::IntegrationTest
  setup do
    shifts(:site_visit).update!(persona: shifts(:month_end).persona)
    messages(:sam_text).update!(needs: %w[ extension ],
      replies: messages(:sam_text).replies + [ { "id" => "r3", "text" => "Why?", "outcome" => "ask_why", "response" => "For the team list." } ])
    @attempt = ShiftAttempt.start(user: users(:one), shift: shifts(:site_visit))
    @attempt.read(messages(:sam_text))
    @ref = @attempt.message_ref(messages(:sam_text))
    sign_in_as users(:one)
  end

  test "the details box lists the player's chips, and sending some shows what was sent and the same answer as always" do
    get shift_attempt_path(@attempt)
    assert_select "[data-testid=details-box] input[name='chips[]'][value=extension]"

    post shift_attempt_message_details_share_path(@attempt, @ref), params: { chips: %w[ extension ] }, as: :turbo_stream

    assert_response :success
    assert_select "turbo-stream[target=shift_reader] template [data-testid=sent-details]", text: /Desk extension: #{@attempt.persona.extension}/
    assert_select "turbo-stream[target=shift_reader] template [data-testid=details-response]", text: Message::DEFAULT_SHARE_RESPONSE
    assert_no_match(/internal|sensitivity|needs/, response.body)
  end

  test "nothing picked is refused" do
    post shift_attempt_message_details_share_path(@attempt, @ref), params: { chips: [] }, as: :turbo_stream

    assert_response :unprocessable_content
  end
end
