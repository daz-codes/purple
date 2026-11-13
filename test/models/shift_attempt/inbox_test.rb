require "test_helper"

class ShiftAttempt::InboxTest < ActiveSupport::TestCase
  setup do
    @attempt = ShiftAttempt.start(user: users(:one), shift: shifts(:month_end))
  end

  test "dealing with a message removes it from the inbox and can bring new ones, which show first" do
    assert_equal %w[ newsletter real_invoice ], @attempt.inbox_messages.map(&:key).sort

    @attempt.archive(messages(:newsletter))

    assert_equal "fake_invoice", @attempt.inbox_messages.first.key
    assert_equal %w[ fake_invoice real_invoice ], @attempt.inbox_messages.map(&:key).sort
    assert_equal [ messages(:newsletter) ], @attempt.archived_messages
  end

  test "messages that arrive together are shuffled per attempt, but stay put within it" do
    orders = 12.times.map do
      attempt = ShiftAttempt.new(token: SecureRandom.base58(32), shift: shifts(:month_end))
      attempt.arrived_messages.map(&:key)
    end

    assert_equal 2, orders.uniq.size
    assert_equal @attempt.arrived_messages, @attempt.reload.arrived_messages
  end

  test "messages brought by the same move are shuffled too, so a fake's place never says which is which" do
    orders = 12.times.map do
      attempt = ShiftAttempt.create!(user: users(:two), shift: shifts(:month_end), status: "completed", completed_at: Time.current, score: 0)
      AttemptAction.create!(shift_attempt: attempt, kind: "archive_message", target_key: "real_invoice", at_seconds: 0)
      attempt.reload.arrived_messages.first(2).map(&:key) # the fake invoice and the thank-you arrive together
    end

    assert_equal [ %w[ fake_invoice supplier_thanks ] ], orders.map(&:sort).uniq
    assert_equal 2, orders.uniq.size
  end

  test "refs are opaque, different per attempt, and find only arrived messages" do
    ref = @attempt.message_ref(messages(:real_invoice))
    other = ShiftAttempt.start(user: users(:two), shift: shifts(:month_end))

    assert_match(/\A\h{16}\z/, ref)
    assert_not_equal ref, other.message_ref(messages(:real_invoice))
    assert_equal messages(:real_invoice), @attempt.find_arrived_message(ref)
    assert_nil @attempt.find_arrived_message(@attempt.message_ref(messages(:fake_invoice)))
  end

  test "a message removed by a re-import leaves the inbox, and scoring still works" do
    @attempt.read(messages(:newsletter))
    messages(:newsletter).destroy!

    assert_equal %w[ real_invoice ], @attempt.reload.inbox_messages.map(&:key)
    assert_nothing_raised { @attempt.scorecard.total }
  end
end
