require "test_helper"

class ShiftAttempts::CompletionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @attempt = ShiftAttempt.start(user: users(:one), shift: shifts(:month_end))
    sign_in_as users(:one)
  end

  test "ending the shift shows the results" do
    post shift_attempt_completion_path(@attempt)

    assert_redirected_to shift_attempt_path(@attempt)
    assert @attempt.reload.completed?

    follow_redirect!
    assert_select "[data-testid=score]", "0"
    assert_select "h1", "Month-end"
  end

  test "ending a shift that's already over still shows the results" do
    @attempt.end_shift
    post shift_attempt_completion_path(@attempt), as: :turbo_stream

    assert_redirected_to shift_attempt_path(@attempt)
  end
end
