require "test_helper"

class MissionAttempts::Messages::ArchivesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @attempt = MissionAttempt.start(user: users(:one), mission: missions(:month_end))
    sign_in_as users(:one)
  end

  test "archiving moves the message out of the inbox, and new messages are announced" do
    post mission_attempt_message_archive_path(@attempt, @attempt.message_ref(messages(:newsletter))), as: :turbo_stream

    assert_response :success
    assert @attempt.reload.archived?(messages(:newsletter))
    assert_select "turbo-stream[target=mission_inbox] template", text: /Done \(1\)/
    assert_select "turbo-stream[target=mission_notice] template", text: "1 new message arrived."
  end

  test "dealing with the last message ends the mission and goes to the debrief" do
    @attempt.archive(messages(:newsletter))
    @attempt.report(messages(:fake_invoice))
    @attempt.archive(messages(:real_invoice))
    post mission_attempt_message_archive_path(@attempt, @attempt.message_ref(messages(:supplier_thanks))), as: :turbo_stream

    assert_redirected_to mission_attempt_path(@attempt)
    assert @attempt.reload.completed?
  end
end
