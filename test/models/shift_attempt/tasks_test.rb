require "test_helper"

class ShiftAttempt::TasksTest < ActiveSupport::TestCase
  setup do
    @attempt = ShiftAttempt.start(user: users(:one), shift: shifts(:month_end))
  end

  test "tasks become overdue once the clock passes their deadline" do
    task = tasks(:pay_supplier)
    @attempt.update!(clock_minutes: 20)
    assert_not @attempt.task_overdue?(task)

    @attempt.expand_headers(messages(:real_invoice))
    assert @attempt.task_overdue?(task)
  end

  test "a task is resolved when every message that could complete it is reported" do
    assert_not @attempt.all_tasks_resolved?

    @attempt.attempt_actions.create!(kind: "report_message", target_key: "real_invoice", minute: 0)
    assert @attempt.reload.all_tasks_resolved?
  end

  test "a task with no completing link doesn't count as resolved" do
    links(:real_invoice_link).destroy!
    @attempt.attempt_actions.create!(kind: "report_message", target_key: "real_invoice", minute: 0)

    assert_not @attempt.reload.all_tasks_resolved?
  end

  test "a task is completed from its portal page, costs two minutes and can only be done once" do
    @attempt.visit(links(:real_invoice_link))
    @attempt.complete_task

    assert @attempt.task_completed?(tasks(:pay_supplier))
    assert_equal [ "complete_task", "pay_supplier", 2 ],
      [ @attempt.actions.last.kind, @attempt.actions.last.target_key, @attempt.actions.last.cost_minutes ]
  end

  test "completing the last task ends the shift" do
    @attempt.visit(links(:real_invoice_link))
    @attempt.complete_task

    assert @attempt.completed?
  end

  test "a task can't be completed from a page that isn't its portal" do
    @attempt.wait_for_mail
    @attempt.visit(links(:fake_invoice_link))

    assert_raises(ShiftAttempt::Rejected, match: /no task/) { @attempt.complete_task }
    assert_not @attempt.task_completed?(tasks(:pay_supplier))
  end
end
