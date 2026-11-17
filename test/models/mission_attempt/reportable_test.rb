require "test_helper"

class MissionAttempt::ReportableTest < ActiveSupport::TestCase
  setup do
    @attempt = MissionAttempt.start(user: users(:one), mission: missions(:month_end))
  end

  test "reporting deals with a message, and says nothing about whether it was right" do
    @attempt.report(messages(:real_invoice))

    assert @attempt.reported?(messages(:real_invoice))
    assert_equal [ messages(:real_invoice) ], @attempt.reported_messages
    assert_raises(MissionAttempt::Rejected, match: /already dealt with/) { @attempt.read(messages(:real_invoice)) }
  end
end
