require "test_helper"

class TargetOptionTest < ActiveSupport::TestCase
  test "a card costs its technique's cost plus any extra" do
    assert_equal 3, target_options(:bank_change).cost
    assert_equal 1 + 2, target_options(:overdue).cost
  end

  test "only pretexts have a subject, in the database too" do
    assert_not target_options(:spoof).tap { |card| card.subject = "Hi" }.valid?
    assert_not target_options(:bank_change).tap { |card| card.subject = nil }.valid?
    assert_raises(ActiveRecord::StatementInvalid) { target_options(:link).update_column(:subject, "Hi") }
  end

  test "relevance is 0 to 3" do
    assert_not target_options(:bank_change).tap { |card| card.relevance = 4 }.valid?
  end
end
