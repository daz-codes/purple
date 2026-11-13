require "test_helper"

# Showing full headers (free) and calling the sender back (adds 30 seconds).
class ShiftAttempt::CheckingTest < ActiveSupport::TestCase
  setup do
    @attempt = ShiftAttempt.start(user: users(:one), shift: shifts(:month_end))
  end

  test "calling the sender back gets their scripted reply, or no answer, and adds 30 seconds" do
    @attempt.verify_sender(messages(:real_invoice))
    @attempt.verify_sender(messages(:newsletter))

    assert_equal "Tidemark confirm they sent it.", @attempt.verification_reply(messages(:real_invoice))
    assert_equal "Nobody picked up.", @attempt.verification_reply(messages(:newsletter))
    assert_equal 60, @attempt.reload.penalty_seconds
  end

  test "headers and call-backs only happen once per message, and headers are free" do
    @attempt.expand_headers(messages(:real_invoice))
    @attempt.verify_sender(messages(:real_invoice))

    assert @attempt.headers_expanded?(messages(:real_invoice))
    assert_raises(ShiftAttempt::Rejected) { @attempt.expand_headers(messages(:real_invoice)) }
    assert_raises(ShiftAttempt::Rejected) { @attempt.verify_sender(messages(:real_invoice)) }
    assert_equal 30, @attempt.reload.penalty_seconds
  end
end
