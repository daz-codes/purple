require "test_helper"

class MessageTest < ActiveSupport::TestCase
  test "phish? is the opposite of legit" do
    assert messages(:fake_invoice).phish?
    assert_not messages(:real_invoice).phish?
  end

  test "keys are unique within a shift" do
    duplicate = messages(:real_invoice).dup
    assert_not duplicate.valid?
  end

  test "destroying a message removes its links, red flags and technique tags" do
    message = messages(:fake_invoice)

    assert_difference -> { Link.count } => -1, -> { RedFlag.count } => -1, -> { MessageTechnique.count } => -1 do
      message.destroy
    end
  end
end
