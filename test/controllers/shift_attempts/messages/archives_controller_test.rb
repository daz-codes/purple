require "test_helper"

class ShiftAttempts::Messages::ArchivesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @attempt = ShiftAttempt.start(user: users(:one), shift: shifts(:month_end))
    sign_in_as users(:one)
  end

  test "archiving moves the message out of the inbox, and new messages are announced" do
    post shift_attempt_message_archive_path(@attempt, @attempt.message_ref(messages(:newsletter))), as: :turbo_stream

    assert_response :success
    assert @attempt.reload.archived?(messages(:newsletter))
    assert_select "turbo-stream[target=shift_inbox] template", text: /Done \(1\)/
    assert_select "turbo-stream[target=shift_notice] template", text: "1 new message arrived."
  end

  test "dealing with the last message ends the shift and goes to the debrief" do
    @attempt.archive(messages(:newsletter))
    @attempt.report(messages(:fake_invoice))
    @attempt.archive(messages(:real_invoice))
    post shift_attempt_message_archive_path(@attempt, @attempt.message_ref(messages(:supplier_thanks))), as: :turbo_stream

    assert_redirected_to shift_attempt_path(@attempt)
    assert @attempt.reload.completed?
  end
end
