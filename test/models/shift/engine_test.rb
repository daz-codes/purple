require "test_helper"

# The fixture shift is 30 minutes long. real_invoice (m1) arrives at minute 0 and holds the link
# for the only task, due at minute 20; fake_invoice (m2) arrives at minute 3.
class Shift::EngineTest < ActiveSupport::TestCase
  setup do
    @attempt = ShiftAttempt.start(user: users(:one), shift: shifts(:month_end))
    @engine = Shift::Engine.new(@attempt)
  end

  test "reading is free and checking costs the shift's configured minutes" do
    @engine.perform("open_message", message_ref: "m1")
    assert_equal 0, @attempt.clock_minutes

    @engine.perform("expand_headers", message_ref: "m1")
    assert_equal 1, @attempt.clock_minutes

    @engine.perform("verify_sender", message_ref: "m1")
    assert_equal 6, @attempt.clock_minutes

    @engine.perform("report_message", message_ref: "m2")
    assert_equal 7, @attempt.clock_minutes
  end

  test "a shift can override action costs" do
    shifts(:month_end).update!(action_costs: { "expand_headers" => 4 })

    @engine.perform("expand_headers", message_ref: "m1")
    assert_equal 4, @attempt.clock_minutes
  end

  test "every action is logged with the minute it started and what it cost" do
    @engine.perform("expand_headers", message_ref: "m1")
    @engine.perform("verify_sender", message_ref: "m1")

    actions = @attempt.attempt_actions.reload
    assert_equal [ [ "expand_headers", "real_invoice", 0, 1 ], [ "verify_sender", "real_invoice", 1, 5 ] ],
      actions.map { |action| [ action.kind, action.target_key, action.minute, action.cost_minutes ] }
    assert_equal "Nobody picked up.", actions.last.result["reply"]
  end

  test "the action log is append-only" do
    action = @engine.perform("open_message", message_ref: "m1")

    assert_raises(ActiveRecord::ReadOnlyRecord) { action.update!(minute: 5) }
  end

  test "messages arrive when the clock reaches them" do
    assert_equal %w[ real_invoice ], @attempt.inbox_messages.map(&:key)
    assert_raises(Shift::Engine::Rejected, match: /isn't in your inbox/) { @engine.perform("open_message", message_ref: "m2") }

    @engine.perform("verify_sender", message_ref: "m1")

    assert_equal %w[ fake_invoice real_invoice ], @attempt.inbox_messages.map(&:key)
    @engine.perform("open_message", message_ref: "m2")
  end

  test "waiting moves the clock to the next arrival" do
    @engine.perform("wait")

    assert_equal 3, @attempt.clock_minutes
    assert_equal "wait", @attempt.attempt_actions.last.kind
    assert_equal 3, @attempt.attempt_actions.last.cost_minutes
    assert_raises(Shift::Engine::Rejected, match: /Nothing else is due/) { @engine.perform("wait") }
  end

  test "actions that don't fit in the time left are rejected" do
    @attempt.update!(clock_minutes: 27)

    assert_raises(Shift::Engine::Rejected, match: /takes 5 min and you have 3/) { @engine.perform("verify_sender", message_ref: "m1") }
    assert_equal 27, @attempt.reload.clock_minutes
  end

  test "the shift times out when the clock reaches the budget, and later actions are rejected" do
    @attempt.update!(clock_minutes: 25)
    @engine.perform("verify_sender", message_ref: "m1")

    assert @attempt.timed_out?
    assert_equal 30, @attempt.clock_minutes
    assert_not_nil @attempt.completed_at
    assert_raises(Shift::Engine::Rejected, match: /over/) { @engine.perform("open_message", message_ref: "m1") }
  end

  test "tasks become overdue once the clock passes their deadline" do
    task = tasks(:pay_supplier)
    @attempt.update!(clock_minutes: 20)
    assert_not @attempt.task_overdue?(task)

    @engine.perform("expand_headers", message_ref: "m1")
    assert @attempt.task_overdue?(task)
  end

  test "reporting removes a message from the inbox and it can't be acted on again" do
    @engine.perform("wait")
    @engine.perform("open_message", message_ref: "m2")
    @engine.perform("report_message", message_ref: "m2")

    assert_equal %w[ real_invoice ], @attempt.inbox_messages.map(&:key)
    assert_nil @attempt.current_message
    assert_raises(Shift::Engine::Rejected, match: /already reported/) { @engine.perform("open_message", message_ref: "m2") }
  end

  test "headers and call-backs only happen once per message" do
    @engine.perform("expand_headers", message_ref: "m1")
    @engine.perform("verify_sender", message_ref: "m1")

    assert_raises(Shift::Engine::Rejected) { @engine.perform("expand_headers", message_ref: "m1") }
    assert_raises(Shift::Engine::Rejected) { @engine.perform("verify_sender", message_ref: "m1") }
    assert_equal 6, @attempt.reload.clock_minutes
  end

  test "unknown actions, and actions the player can't send directly, are rejected" do
    %w[ complete_task end_shift submit_credentials destroy ].each do |kind|
      assert_raises(Shift::Engine::Rejected, kind) { @engine.perform(kind, message_ref: "m1") }
    end
    assert_raises(Shift::Engine::Rejected) { @engine.perform("open_message", message_ref: "fake_invoice") }
    assert_empty @attempt.attempt_actions.reload
  end

  test "the shift ends when every task is resolved" do
    # Reporting the only message that can complete the task makes the task impossible.
    @engine.perform("report_message", message_ref: "m1")

    assert @attempt.completed?
  end

  test "ending the shift scores it from the log" do
    @engine.perform("wait")
    @engine.perform("report_message", message_ref: "m2")
    @engine.end_shift

    assert @attempt.completed?
    assert_equal "end_shift", @attempt.attempt_actions.last.kind
    assert_equal [ -20, 30, 10 ], [ @attempt.productivity_score, @attempt.security_score, @attempt.score ]
  end

  test "only a confirmed player's first finished attempt is scored" do
    @engine.end_shift
    assert @attempt.scored?

    second = ShiftAttempt.start(user: users(:one), shift: shifts(:month_end))
    Shift::Engine.new(second).end_shift
    assert_not second.scored?

    unconfirmed = ShiftAttempt.start(user: users(:unconfirmed), shift: shifts(:month_end))
    Shift::Engine.new(unconfirmed).end_shift
    assert_not unconfirmed.scored?
  end
end
