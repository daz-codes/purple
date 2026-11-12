require "test_helper"

class ShiftAttempt::InboxTest < ActiveSupport::TestCase
  setup do
    @attempt = ShiftAttempt.start(user: users(:one), shift: shifts(:month_end))
  end

  test "messages arrive when the clock reaches them" do
    assert_equal %w[ real_invoice ], @attempt.inbox_messages.map(&:key)
    assert_raises(ShiftAttempt::Rejected, match: /isn't in your inbox/) { @attempt.read(messages(:fake_invoice)) }

    @attempt.verify_sender(messages(:real_invoice))

    assert_equal %w[ fake_invoice real_invoice ], @attempt.inbox_messages.map(&:key)
    assert_nothing_raised { @attempt.read(messages(:fake_invoice)) }
  end

  test "waiting moves the clock to the next arrival" do
    @attempt.wait_for_mail

    assert_equal 3, @attempt.clock_minutes
    assert_equal [ "wait", 3 ], [ @attempt.actions.last.kind, @attempt.actions.last.cost_minutes ]
    assert_raises(ShiftAttempt::Rejected, match: /Nothing else is due/) { @attempt.wait_for_mail }
  end

  test "messages are found by their opaque ref, never by their key or position" do
    ref = @attempt.message_ref(messages(:real_invoice))

    assert_match(/\A\h{16}\z/, ref)
    assert_equal messages(:real_invoice), @attempt.find_arrived_message(ref)
    assert_nil @attempt.find_arrived_message("real_invoice")
    assert_nil @attempt.find_arrived_message("m1")
    assert_nil @attempt.find_arrived_message(@attempt.message_ref(messages(:fake_invoice))) # hasn't arrived yet
  end

  test "message refs survive re-ordering and differ between attempts" do
    ref = @attempt.message_ref(messages(:real_invoice))
    messages(:real_invoice).update!(position: 99)

    assert_equal messages(:real_invoice), @attempt.reload.find_arrived_message(ref)
    other = ShiftAttempt.start(user: users(:two), shift: shifts(:month_end))
    assert_not_equal ref, other.message_ref(messages(:real_invoice))
  end

  test "a message removed by a re-import leaves the inbox, and scoring still works" do
    @attempt.wait_for_mail
    @attempt.report(messages(:fake_invoice))
    ref = @attempt.message_ref(messages(:real_invoice))
    messages(:real_invoice).destroy!

    assert_nil @attempt.reload.find_arrived_message(ref)
    assert_nothing_raised { @attempt.scorecard.total }
  end
end
