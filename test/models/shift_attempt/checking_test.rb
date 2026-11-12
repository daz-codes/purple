require "test_helper"

# Showing full headers and calling the sender back.
class ShiftAttempt::CheckingTest < ActiveSupport::TestCase
  setup do
    @attempt = ShiftAttempt.start(user: users(:one), shift: shifts(:month_end))
    @attempt.wait_for_mail
  end

  test "calling the sender back gets their scripted reply, or no answer" do
    @attempt.verify_sender(messages(:fake_invoice))
    @attempt.verify_sender(messages(:real_invoice))

    assert_equal "Northwind haven't changed their bank details.", @attempt.verification_reply(messages(:fake_invoice))
    assert_equal "Nobody picked up.", @attempt.verification_reply(messages(:real_invoice))
  end

  test "headers and call-backs only happen once per message" do
    @attempt.expand_headers(messages(:real_invoice))
    @attempt.verify_sender(messages(:real_invoice))

    assert @attempt.headers_expanded?(messages(:real_invoice))
    assert_raises(ShiftAttempt::Rejected) { @attempt.expand_headers(messages(:real_invoice)) }
    assert_raises(ShiftAttempt::Rejected) { @attempt.verify_sender(messages(:real_invoice)) }
    assert_equal 9, @attempt.reload.clock_minutes
  end
end
