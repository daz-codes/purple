require "test_helper"

class ShiftAttempts::Tabs::TaskCompletionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @attempt = ShiftAttempt.start(user: users(:one), shift: shifts(:month_end))
    sign_in_as users(:one)
  end

  test "doing the task on its portal page completes it" do
    @attempt.visit(links(:real_invoice_link))
    post shift_attempt_tab_task_completion_path(@attempt), as: :turbo_stream

    # It was the only task, so the shift is over.
    assert_redirected_to shift_attempt_path(@attempt)
    assert @attempt.reload.task_completed?(tasks(:pay_supplier))
  end

  test "there's no task to do without its portal open" do
    post shift_attempt_tab_task_completion_path(@attempt), as: :turbo_stream

    assert_response :unprocessable_content
  end
end
