require "test_helper"

class ShiftTest < ActiveSupport::TestCase
  test "orders messages by position" do
    assert_equal %w[ real_invoice newsletter fake_invoice supplier_thanks ], shifts(:month_end).messages.map(&:key)
  end

  test "has a positive target time" do
    shift = shifts(:month_end)
    shift.par_minutes = 0
    assert_not shift.valid?
  end

  test "the database rejects an unknown kind" do
    assert_raises(ActiveRecord::StatementInvalid) { shifts(:month_end).update_column(:kind, "voice") }
  end

  test "uses its slug in URLs" do
    assert_equal "month-end", shifts(:month_end).to_param
  end
end
