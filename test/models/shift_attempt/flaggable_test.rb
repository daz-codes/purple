require "test_helper"

# The fake invoice's first paragraph: "Please pay today. Our bank details have changed."
class ShiftAttempt::FlaggableTest < ActiveSupport::TestCase
  setup do
    @attempt = ShiftAttempt.start(user: users(:one), shift: shifts(:month_end))
    @attempt.archive(messages(:newsletter))
    @fake = messages(:fake_invoice)
  end

  test "a whole part can be flagged, for free, and flagging it again takes the flag off" do
    @attempt.flag(@fake, "from")
    assert_equal [ flag("from") ], @attempt.flags_on(@fake)
    assert_equal({ "anchor" => "from" }, @attempt.actions.last.result)

    @attempt.flag(@fake, "from")
    assert_empty @attempt.flags_on(@fake)
    assert_equal 0, @attempt.reload.penalty_seconds
  end

  test "a sentence click is stored as the sentence's range, so it's the same flag as dragging over the same words" do
    @attempt.flag(@fake, "p1s2")
    assert_equal [ flag("p1", 18, 48) ], @attempt.flags_on(@fake)
    assert_equal "Our bank details have changed.", @fake.paragraphs["p1"].text[18...48]

    @attempt.flag(@fake, "p1", from: "18", to: "48")
    assert_empty @attempt.flags_on(@fake)
  end

  test "a highlight is trimmed of whitespace, and must be some text inside its paragraph" do
    @attempt.flag(@fake, "p1", from: 17, to: 27) # " Our bank "
    assert_equal [ flag("p1", 18, 26) ], @attempt.flags_on(@fake)

    [ [ 17, 18 ], [ 40, 99 ], [ 5, 2 ], [ "x", 3 ] ].each do |from, to|
      assert_raises(ShiftAttempt::Rejected, match: /nothing to flag/) { @attempt.flag(@fake, "p1", from:, to:) }
    end
  end

  test "only parts the message has, and the player can see, can be flagged" do
    %w[ p9 p9s1 p1s9 l9 a9 reply_to ].each do |anchor|
      assert_raises(ShiftAttempt::Rejected, match: /nothing to flag/) { @attempt.flag(@fake, anchor) }
    end
    assert_raises(ShiftAttempt::Rejected, match: /nothing to flag/) { @attempt.flag(@fake, "p1") } # no range

    @attempt.expand_headers(@fake)
    assert_nothing_raised { @attempt.flag(@fake, "reply_to") }
  end

  test "flags belong to their message, and a message that's been dealt with can't be flagged" do
    @attempt.flag(@fake, "from")
    assert_empty @attempt.flags_on(messages(:real_invoice))

    @attempt.report(@fake)
    assert_raises(ShiftAttempt::Rejected, match: /already dealt with/) { @attempt.flag(@fake, "subject") }
  end

  private
    def flag(anchor, from = nil, to = nil)
      ShiftAttempt::Flag.new(anchor:, from:, to:)
    end
end
