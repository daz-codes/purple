require "test_helper"

class ShiftAttempt::ScorecardTest < ActiveSupport::TestCase
  setup do
    @shift = shifts(:month_end) # one task: pay_supplier, 40 points, due at minute 20
  end

  test "a task completed on time earns its points" do
    result = scorecard(action("complete_task", "pay_supplier", minute: 18, cost: 2))

    assert_equal 40, result.productivity
    assert result.tasks.first.on_time?
  end

  test "a task completed after its deadline earns half" do
    result = scorecard(action("complete_task", "pay_supplier", minute: 19, cost: 2))

    assert_equal 20, result.productivity
    assert result.tasks.first.late?
  end

  test "a task never completed loses half its points" do
    result = scorecard

    assert_equal(-20, result.productivity)
    assert result.tasks.first.missed?
  end

  test "only the first completion of a task counts" do
    result = scorecard(action("complete_task", "pay_supplier", minute: 25), action("complete_task", "pay_supplier", minute: 1))

    assert result.tasks.first.late?
  end

  test "reporting a phish scores, reporting a legitimate message costs, and repeats don't count" do
    assert_equal 30, scorecard(action("report_message", "fake_invoice"), action("report_message", "fake_invoice")).security
    assert_equal(-15, scorecard(action("report_message", "real_invoice")).security)
  end

  test "a report of a message that no longer exists counts for nothing" do
    assert_equal 0, scorecard(action("report_message", "deleted_by_reimport")).security
  end

  test "a compromise costs 50" do
    assert_equal(-50, scorecard(action("submit_credentials", "fake_invoice")).security)
  end

  test "the total is productivity plus security, never below zero" do
    assert_equal 10, scorecard(action("report_message", "fake_invoice")).total # -20 + 30
    assert_equal 0, scorecard(action("report_message", "real_invoice")).total # -20 - 15
  end

  test "the live productivity meter counts only completed work and never penalises unfinished tasks" do
    assert_equal 0, scorecard.productivity_meter
    assert_equal 100, scorecard(action("complete_task", "pay_supplier", minute: 5)).productivity_meter
    assert_equal 50, scorecard(action("complete_task", "pay_supplier", minute: 25)).productivity_meter
  end

  test "the live security meter doesn't reveal whether a report was right" do
    assert_equal 100, scorecard(action("report_message", "fake_invoice")).security_meter
    assert_equal 100, scorecard(action("report_message", "real_invoice")).security_meter
    assert_equal 50, scorecard(action("submit_credentials", "fake_invoice")).security_meter
  end

  private
    def action(kind, target_key, minute: 0, cost: 0)
      AttemptAction.new(kind:, target_key:, minute:, cost_minutes: cost)
    end

    def scorecard(*actions)
      ShiftAttempt::Scorecard.new(shift: @shift, actions:)
    end
end
