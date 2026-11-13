require "test_helper"

# Month-end: the real invoice and the newsletter arrive at the start; the fake invoice once any one
# message has been dealt with; the supplier's thank-you once the real invoice has been.
class ShiftAttempt::ArrivalsTest < ActiveSupport::TestCase
  setup do
    @messages = shifts(:month_end).messages.to_a
  end

  test "only the start messages are there at first" do
    assert_equal %w[ real_invoice newsletter ], arrivals.messages.map(&:key)
    assert_equal [ 0, 0 ], arrivals.all.map(&:at_seconds)
  end

  test "dealing with any message brings the ones waiting for a count, at the time it was dealt with" do
    result = arrivals(action("archive_message", "newsletter", at: 40))

    assert_equal %w[ real_invoice newsletter fake_invoice ], result.messages.map(&:key)
    assert_equal 40, result.at_seconds(messages(:fake_invoice))
  end

  test "a follow-up arrives once its message has been dealt with, whichever way" do
    result = arrivals(action("report_message", "real_invoice", at: 10, penalty: 30))

    assert_equal %w[ real_invoice newsletter fake_invoice supplier_thanks ], result.messages.map(&:key)
    assert_equal 40, result.at_seconds(messages(:supplier_thanks)) # its time includes the move's penalty
  end

  test "only dealing with a message counts: reading it, or dealing with one that hasn't arrived, doesn't" do
    assert_equal 2, arrivals(action("open_message", "real_invoice"), action("archive_message", "supplier_thanks")).messages.size
  end

  test "reachable: dealing with everything that arrives must bring every message" do
    assert_equal %w[ fake_invoice newsletter real_invoice supplier_thanks ], ShiftAttempt::Arrivals.reachable(@messages).sort

    @messages.find { |message| message.key == "fake_invoice" }.arrives_after_handled = 9
    assert_not_includes ShiftAttempt::Arrivals.reachable(@messages), "fake_invoice"
  end

  private
    def arrivals(*actions)
      ShiftAttempt::Arrivals.new(@messages, actions)
    end

    def action(kind, key, at: 0, penalty: 0)
      AttemptAction.new(kind:, target_key: key, at_seconds: at, penalty_seconds: penalty)
    end
end
