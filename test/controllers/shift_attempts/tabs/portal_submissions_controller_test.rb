require "test_helper"

class ShiftAttempts::Tabs::PortalSubmissionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @attempt = ShiftAttempt.start(user: users(:one), shift: shifts(:month_end))
    @attempt.visit(links(:real_invoice_link))
    sign_in_as users(:one)
  end

  test "the portal page offers its button, and pressing it shows the same plain confirmation a bait page does" do
    get shift_attempt_path(@attempt)
    assert_select "dialog button", text: "Approve invoice"

    post shift_attempt_tab_portal_submission_path(@attempt), as: :turbo_stream

    assert_response :success
    assert @attempt.reload.used_portal?(messages(:real_invoice))
    assert_select "turbo-stream[target=shift_browser] template dialog [role=status]", text: /that's been submitted/
  end

  test "there's nothing to press twice" do
    @attempt.use_portal
    post shift_attempt_tab_portal_submission_path(@attempt), as: :turbo_stream

    assert_response :unprocessable_content
  end
end
