require "test_helper"

class MissionAttempts::Tabs::PortalSubmissionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @attempt = MissionAttempt.start(user: users(:one), mission: missions(:month_end))
    @attempt.visit(links(:real_invoice_link))
    sign_in_as users(:one)
  end

  test "the portal page offers its button, and pressing it shows the same plain confirmation a bait page does" do
    get mission_attempt_path(@attempt)
    assert_select "dialog button", text: "Approve invoice"

    post mission_attempt_tab_portal_submission_path(@attempt), as: :turbo_stream

    assert_response :success
    assert @attempt.reload.used_portal?(messages(:real_invoice))
    assert_select "turbo-stream[target=mission_browser] template dialog [role=status]", text: /that's been submitted/
  end

  test "there's nothing to press twice" do
    @attempt.use_portal
    post mission_attempt_tab_portal_submission_path(@attempt), as: :turbo_stream

    assert_response :unprocessable_content
  end

  test "a portal that needs details has a field for each, filled by picking a chip, and only the chip's id is posted" do
    messages(:real_invoice).update!(needs: %w[ staff_number ])
    get mission_attempt_path(@attempt)
    assert_select "dialog select[name='details[]'] option[value=staff_number]"
    assert_select "dialog input[type=text]", count: 0

    post mission_attempt_tab_portal_submission_path(@attempt), params: { details: [ "staff_number" ] }, as: :turbo_stream

    assert_response :success
    assert @attempt.reload.scorecard.message_result_for("real_invoice").done?
  end
end
