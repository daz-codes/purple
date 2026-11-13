require "test_helper"

class ShiftAttempt::ReportableTest < ActiveSupport::TestCase
  setup do
    @attempt = ShiftAttempt.start(user: users(:one), shift: shifts(:month_end))
  end

  test "reporting deals with a message, and says nothing about whether it was right" do
    @attempt.report(messages(:real_invoice))

    assert @attempt.reported?(messages(:real_invoice))
    assert_equal [ messages(:real_invoice) ], @attempt.reported_messages
    assert_raises(ShiftAttempt::Rejected, match: /already dealt with/) { @attempt.read(messages(:real_invoice)) }
  end
end
