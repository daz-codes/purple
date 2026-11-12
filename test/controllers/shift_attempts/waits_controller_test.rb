require "test_helper"

class ShiftAttempts::WaitsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @attempt = ShiftAttempt.start(user: users(:one), shift: shifts(:month_end))
    sign_in_as users(:one)
  end

  test "waiting announces the new mail" do
    post shift_attempt_wait_path(@attempt), as: :turbo_stream

    assert_equal 3, @attempt.reload.clock_minutes
    assert_select "turbo-stream[target=shift_notice] template", text: "1 new message arrived."
  end

  test "waiting with nothing left to arrive is refused" do
    @attempt.wait_for_mail
    post shift_attempt_wait_path(@attempt), as: :turbo_stream

    assert_response :unprocessable_content
  end
end
