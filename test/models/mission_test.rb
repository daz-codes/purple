require "test_helper"

class MissionTest < ActiveSupport::TestCase
  test "orders messages by position" do
    assert_equal %w[ real_invoice newsletter fake_invoice supplier_thanks ], missions(:month_end).messages.map(&:key)
  end

  test "has a positive target time" do
    mission = missions(:month_end)
    mission.par_minutes = 0
    assert_not mission.valid?
  end

  test "the database rejects an unknown kind" do
    assert_raises(ActiveRecord::StatementInvalid) { missions(:month_end).update_column(:kind, "voice") }
  end

  test "uses its slug in URLs" do
    assert_equal "month-end", missions(:month_end).to_param
  end
end
