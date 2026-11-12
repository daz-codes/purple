require "test_helper"

class ShiftAttempt::FlaggableTest < ActiveSupport::TestCase
  setup do
    @attempt = ShiftAttempt.start(user: users(:one), shift: shifts(:month_end))
    @attempt.wait_for_mail
    @phish = messages(:fake_invoice)
  end

  test "any part of a message can be flagged, for free, and flagging it again takes the flag off" do
    @attempt.flag(@phish, "p1")
    @attempt.flag(@phish, "from")
    assert_equal %w[ p1 from ], @attempt.flagged_anchors(@phish)
    assert_equal 3, @attempt.clock_minutes

    @attempt.flag(@phish, "p1")
    assert_equal %w[ from ], @attempt.flagged_anchors(@phish)
  end

  test "flags belong to their message" do
    @attempt.flag(@phish, "p1")

    assert_empty @attempt.flagged_anchors(messages(:real_invoice))
  end

  test "only parts the message has can be flagged" do
    assert_raises(ShiftAttempt::Rejected, match: /nothing to flag/) { @attempt.flag(@phish, "p9") }
    assert_raises(ShiftAttempt::Rejected, match: /nothing to flag/) { @attempt.flag(@phish, "lookalike") }
    assert_empty @attempt.actions.select(&:flag_element?)
  end

  test "To and Reply-To can only be flagged once the full headers are showing" do
    assert_raises(ShiftAttempt::Rejected, match: /nothing to flag/) { @attempt.flag(@phish, "reply_to") }
    assert_raises(ShiftAttempt::Rejected, match: /nothing to flag/) { @attempt.flag(@phish, "to") }

    @attempt.expand_headers(@phish)
    @attempt.flag(@phish, "reply_to")
    assert_equal %w[ reply_to ], @attempt.flagged_anchors(@phish)
  end

  test "a reported message can't be flagged" do
    @attempt.report(@phish)

    assert_raises(ShiftAttempt::Rejected, match: /already reported/) { @attempt.flag(@phish, "from") }
  end
end
