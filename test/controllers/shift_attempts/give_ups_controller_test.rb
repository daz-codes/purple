require "test_helper"

class ShiftAttempts::GiveUpsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @attempt = ShiftAttempt.start(user: users(:one), shift: shifts(:month_end))
    sign_in_as users(:one)
  end

  test "giving up ends the shift and goes to the debrief" do
    post shift_attempt_give_up_path(@attempt), as: :turbo_stream

    assert_redirected_to shift_attempt_path(@attempt)
    assert @attempt.reload.gave_up?

    follow_redirect!
    assert_select "[data-testid=debrief-ending]", text: /You gave up/
  end

  test "giving up a finished shift just goes to its debrief" do
    @attempt.give_up
    post shift_attempt_give_up_path(@attempt), as: :turbo_stream

    assert_redirected_to shift_attempt_path(@attempt)
  end
end
