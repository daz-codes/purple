require "test_helper"

class ShiftAttempts::ClockOffsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @attempt = ShiftAttempt.start(user: users(:one), shift: shifts(:month_end))
    sign_in_as users(:one)
  end

  test "clocking off early ends the shift and goes to the debrief" do
    post shift_attempt_clock_off_path(@attempt), as: :turbo_stream

    assert_redirected_to shift_attempt_path(@attempt)
    assert @attempt.reload.clocked_off?

    follow_redirect!
    assert_select "[data-testid=debrief-ending]", text: /You clocked off/
  end

  test "clocking off early a finished shift just goes to its debrief" do
    @attempt.clock_off
    post shift_attempt_clock_off_path(@attempt), as: :turbo_stream

    assert_redirected_to shift_attempt_path(@attempt)
  end
end
