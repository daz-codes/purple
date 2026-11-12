require "test_helper"

class ShiftAttempt::ReportableTest < ActiveSupport::TestCase
  setup do
    @attempt = ShiftAttempt.start(user: users(:one), shift: shifts(:month_end))
  end

  test "reporting removes a message from the inbox and it can't be acted on again" do
    @attempt.wait_for_mail
    @attempt.report(messages(:fake_invoice))

    assert_equal %w[ real_invoice ], @attempt.inbox_messages.map(&:key)
    assert_equal %w[ fake_invoice ], @attempt.reported_messages.map(&:key)
    assert_raises(ShiftAttempt::Rejected, match: /already reported/) { @attempt.read(messages(:fake_invoice)) }
  end
end
