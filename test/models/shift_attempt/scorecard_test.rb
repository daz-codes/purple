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

  test "a compromise costs 50, once per page or file" do
    link = { "link" => "l1" }
    assert_equal(-50, scorecard(action("click_link", "fake_invoice", result: link), action("submit_credentials", "fake_invoice", result: link),
                                action("submit_credentials", "fake_invoice", result: link)).security)

    file = { "attachment" => "a1" }
    assert_equal(-50, scorecard(action("open_attachment", "fake_invoice", result: file), action("run_download", "fake_invoice", result: file)).security)
  end

  test "opening a trap without falling for it is a near miss" do
    assert_equal(-10, scorecard(action("click_link", "fake_invoice", result: { "link" => "l1" })).security)
    assert_equal(-10, scorecard(action("open_attachment", "fake_invoice", result: { "attachment" => "a1" })).security)
  end

  test "opening legitimate links and documents costs nothing" do
    assert_equal 0, scorecard(action("click_link", "real_invoice", result: { "link" => "l1" }),
                              action("open_attachment", "real_invoice", result: { "attachment" => "a1" })).security
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
    assert_equal 50, scorecard(action("submit_credentials", "fake_invoice", result: { "link" => "l1" })).security_meter
    assert_equal 50, scorecard(action("submit_credentials", "fake_invoice", result: { "link" => "l1" }),
                               action("submit_credentials", "fake_invoice", result: { "link" => "l1" })).security_meter
  end

  test "the live security meter doesn't reveal that a closed page was a trap" do
    assert_equal 100, scorecard(action("click_link", "fake_invoice", result: { "link" => "l1" }),
                                action("close_landing", "fake_invoice", result: { "link" => "l1" })).security_meter
  end

  test "the maximum is every task on time plus every phish that arrived, reported" do
    card = scorecard

    assert_equal 40, card.productivity_max
    assert_equal 30, card.security_max
    assert_equal 70, card.total_max
  end

  test "a phish that arrived after the shift ended still counts, as not reported" do
    card = scorecard(clock_minutes: 2)

    assert_equal %w[ real_invoice fake_invoice ], card.messages.map { |result| result.message.key }
    assert_equal [ true, false ], card.messages.map(&:arrived?)
    assert_equal :arrived_after_shift, card.message_result_for("fake_invoice").outcome
    assert_equal [ 0, 30 ], [ card.security, card.security_max ]
  end

  test "a perfect shift earns three stars, and anything less is judged against the maximum" do
    perfect = scorecard(action("complete_task", "pay_supplier", minute: 5), action("report_message", "fake_invoice"))
    assert perfect.perfect?
    assert_equal 3, perfect.stars

    nearly = scorecard(action("complete_task", "pay_supplier", minute: 5), action("report_message", "fake_invoice"),
                       action("open_attachment", "fake_invoice", result: { "attachment" => "a1" }))
    assert_not nearly.perfect?
    assert_equal 2, nearly.stars # 60 of 70

    assert_equal 0, scorecard.stars
  end

  test "each message is judged on what the player did with it" do
    file = { "attachment" => "a1" }

    assert_equal :reported, outcome("fake_invoice", action("report_message", "fake_invoice"))
    assert_equal :compromised, outcome("fake_invoice", action("open_attachment", "fake_invoice", result: file),
                                       action("run_download", "fake_invoice", result: file), action("report_message", "fake_invoice"))
    assert_equal :near_miss, outcome("fake_invoice", action("open_attachment", "fake_invoice", result: file))
    assert_equal :not_reported, outcome("fake_invoice", action("open_message", "fake_invoice"))

    assert_equal :reported_wrongly, outcome("real_invoice", action("report_message", "real_invoice"))
    assert_equal :used, outcome("real_invoice", action("complete_task", "pay_supplier", minute: 5))
    assert_equal :left_alone, outcome("real_invoice", action("open_message", "real_invoice"))
  end

  test "a message's points add up to the security score" do
    file = { "attachment" => "a1" }
    card = scorecard(action("open_attachment", "fake_invoice", result: file), action("report_message", "fake_invoice"))
    result = card.message_result_for("fake_invoice")

    assert_equal 20, result.points # reported, after a close call
    assert_equal [ "Remittance_4471.pdf.exe" ], result.near_misses.map(&:file_name)
    assert_equal card.security, card.messages.sum(&:points)
  end

  test "a completed task records the minute it was finished" do
    assert_equal 7, scorecard(action("complete_task", "pay_supplier", minute: 5, cost: 2)).tasks.first.completed_at_minute
  end

  private
    def outcome(key, *actions)
      scorecard(*actions).message_result_for(key).outcome
    end

    def action(kind, target_key, minute: 0, cost: 0, result: {})
      AttemptAction.new(kind:, target_key:, minute:, cost_minutes: cost, result:)
    end

    def scorecard(*actions, clock_minutes: nil)
      ShiftAttempt::Scorecard.new(shift: @shift, actions:, clock_minutes:)
    end
end
