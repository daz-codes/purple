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

  test "a task is completed from its portal page, costs two minutes and can only be done once" do
    @attempt.visit(links(:real_invoice_link))
    @attempt.complete_task

    assert @attempt.task_completed?(tasks(:pay_supplier))
    completion = @attempt.actions.find(&:complete_task?)
    assert_equal [ "pay_supplier", 2 ], [ completion.target_key, completion.cost_minutes ]
  end

  # Anything more would tell the player the remaining mail doesn't matter for their tasks.
  test "completing the last task doesn't end the shift, move the clock on or bring mail early" do
    @attempt.visit(links(:real_invoice_link))
    @attempt.complete_task

    assert @attempt.open?
    assert_equal 2, @attempt.clock_minutes
    assert_equal %w[ click_link complete_task ], @attempt.actions.map(&:kind)
    assert_not_includes @attempt.arrived_messages, messages(:fake_invoice)
  end

  test "a task can't be completed from a page that isn't its portal" do
    @attempt.wait_for_mail
    @attempt.visit(links(:fake_invoice_link))

    assert_raises(ShiftAttempt::Rejected, match: /no task/) { @attempt.complete_task }
    assert_not @attempt.task_completed?(tasks(:pay_supplier))
  end
end
