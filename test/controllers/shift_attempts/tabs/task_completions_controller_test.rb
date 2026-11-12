require "test_helper"

class ShiftAttempts::Tabs::TaskCompletionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @attempt = ShiftAttempt.start(user: users(:one), shift: shifts(:month_end))
    sign_in_as users(:one)
  end

  test "doing the task on its portal page completes it" do
    @attempt.visit(links(:real_invoice_link))
    post shift_attempt_tab_task_completion_path(@attempt), as: :turbo_stream

    # It was the only task, but the shift carries on as before.
    assert_response :success
    assert_select "[data-testid=clock]", text: /Minute 2 of 30/
    assert @attempt.reload.task_completed?(tasks(:pay_supplier))
  end

  test "there's no task to do without its portal open" do
    post shift_attempt_tab_task_completion_path(@attempt), as: :turbo_stream

    assert_response :unprocessable_content
  end

  test "a refused move is shown inside the in-game browser as well as behind it" do
    @attempt.update!(clock_minutes: 29) # completing the task takes 2 minutes
    @attempt.visit(links(:real_invoice_link))
    post shift_attempt_tab_task_completion_path(@attempt), as: :turbo_stream

    assert_response :unprocessable_content
    assert_select "turbo-stream[target=shift_notice] template [role=alert]", text: /Not enough time left/
    assert_select "turbo-stream[target=browser_notice] template [role=alert]", text: /Not enough time left/
  end
end
