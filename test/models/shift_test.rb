require "test_helper"

class ShiftTest < ActiveSupport::TestCase
  test "action costs default from the plan and can be overridden per shift" do
    shift = shifts(:month_end)

    assert_equal 0, shift.action_cost(:open_message)
    assert_equal 1, shift.action_cost(:expand_headers)
    assert_equal 5, shift.action_cost(:verify_sender)

    shift.action_costs = { "verify_sender" => 3 }
    assert_equal 3, shift.action_cost(:verify_sender)
  end

  test "rejects unknown or negative action costs" do
    shift = shifts(:month_end)

    shift.action_costs = { "teleport" => 1 }
    assert_not shift.valid?

    shift.action_costs = { "verify_sender" => -1 }
    assert_not shift.valid?
  end

  test "orders messages by position and exposes tasks" do
    shift = shifts(:month_end)

    assert_equal %w[ real_invoice fake_invoice ], shift.messages.map(&:key)
    assert_equal [ tasks(:pay_supplier) ], shift.tasks.to_a
  end

  test "the database rejects an unknown kind" do
    assert_raises(ActiveRecord::StatementInvalid) { shifts(:month_end).update_column(:kind, "voice") }
  end

  test "uses its slug in URLs" do
    assert_equal "month-end", shifts(:month_end).to_param
  end
end
