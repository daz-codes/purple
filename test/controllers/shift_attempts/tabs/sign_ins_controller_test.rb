require "test_helper"

class ShiftAttempts::Tabs::SignInsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @attempt = ShiftAttempt.start(user: users(:one), shift: shifts(:month_end))
    @attempt.archive(messages(:newsletter))
    @attempt.visit(links(:fake_invoice_link))
    sign_in_as users(:one)
  end

  test "the lookalike sign-in form has no named fields, so nothing typed is ever sent" do
    get shift_attempt_path(@attempt)

    sign_in_form = "dialog form[action='#{shift_attempt_tab_sign_in_path(@attempt)}']"
    assert_select "#{sign_in_form} input[type=password][placeholder='Never enter a real password']:not([name])"
    assert_select "#{sign_in_form} input[type=email]:not([name])"
    assert_select "#{sign_in_form} input[name]:not([name=authenticity_token])", count: 0
  end

  test "signing in carries on to the same plain confirmation a real portal shows, and records nothing typed" do
    post shift_attempt_tab_sign_in_path(@attempt), params: { password: "hunter2-would-be-ignored" }, as: :turbo_stream

    assert_response :success
    assert_select "[role=alert]", count: 0
    assert_select "turbo-stream[target=shift_browser] template dialog [role=status]", text: /that's been submitted/
    assert @attempt.reload.scorecard.message_result_for("fake_invoice").compromised?
    assert @attempt.open?
    assert_not_includes @attempt.attempt_actions.to_json, "hunter2"
  end
end
