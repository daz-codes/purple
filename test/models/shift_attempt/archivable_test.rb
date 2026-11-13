require "test_helper"

class ShiftAttempt::ArchivableTest < ActiveSupport::TestCase
  setup do
    @attempt = ShiftAttempt.start(user: users(:one), shift: shifts(:month_end))
  end

  test "archiving deals with a message: it leaves the inbox and nothing more can be done with it" do
    @attempt.read(messages(:newsletter))
    @attempt.archive(messages(:newsletter))

    assert @attempt.archived?(messages(:newsletter))
    assert_nil @attempt.current_message
    assert_not_includes @attempt.inbox_messages, messages(:newsletter)
    assert_raises(ShiftAttempt::Rejected, match: /already dealt with/) { @attempt.archive(messages(:newsletter)) }
    assert_raises(ShiftAttempt::Rejected, match: /already dealt with/) { @attempt.report(messages(:newsletter)) }
  end
end
