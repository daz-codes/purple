require "test_helper"

class ShiftAttempt::ReadingTest < ActiveSupport::TestCase
  setup do
    @attempt = ShiftAttempt.start(user: users(:one), shift: shifts(:month_end))
  end

  test "the last message read is in the reading pane, until it's reported" do
    assert_nil @attempt.current_message
    @attempt.wait_for_mail

    @attempt.read(messages(:real_invoice))
    @attempt.read(messages(:fake_invoice))
    assert_equal messages(:fake_invoice), @attempt.current_message
    assert @attempt.opened?(messages(:real_invoice))

    @attempt.report(messages(:fake_invoice))
    assert_nil @attempt.current_message
  end
end
