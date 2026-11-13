require "test_helper"

class ShiftAttempt::ReadingTest < ActiveSupport::TestCase
  setup do
    @attempt = ShiftAttempt.start(user: users(:one), shift: shifts(:month_end))
  end

  test "the last message read is in the reading pane, until it's dealt with" do
    assert_nil @attempt.current_message

    @attempt.read(messages(:real_invoice))
    @attempt.read(messages(:newsletter))
    assert_equal messages(:newsletter), @attempt.current_message
    assert @attempt.opened?(messages(:real_invoice))

    @attempt.archive(messages(:newsletter))
    assert_nil @attempt.current_message
  end
end
