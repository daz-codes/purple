require "test_helper"

class ShiftAttempt::ReplyableTest < ActiveSupport::TestCase
  setup do
    @attempt = ShiftAttempt.start(user: users(:one), shift: shifts(:site_visit))
    @attempt.wait_for_mail
  end

  test "sending a reply logs only its neutral id and shows the player what they said and what came back" do
    @attempt.send_reply(messages(:sam_text), "r1")

    action = @attempt.actions.last
    assert_equal [ "send_reply", "sam_text", { "reply" => "r1" }, 1 ], [ action.kind, action.target_key, action.result, action.cost_minutes ]
    assert @attempt.replied?(messages(:sam_text))
    assert_equal({ "text" => "Sure, see you there", "response" => "Legend, thanks!" }, @attempt.sent_reply(messages(:sam_text)))
    assert_equal 100, @attempt.scorecard.security_meter
  end

  test "handing over the code compromises the player, and they see it at once" do
    @attempt.send_reply(messages(:it_chat), "r1")

    assert_equal 50, @attempt.scorecard.security_meter
    assert @attempt.open?
    assert @attempt.scorecard.message_result_for("it_chat").gave_in?
  end

  test "refusing is safe" do
    @attempt.send_reply(messages(:it_chat), "r2")

    assert_equal 100, @attempt.scorecard.security_meter
    assert_not @attempt.sender_verified?(messages(:it_chat))
  end

  test "checking with the service desk is the same move as calling the sender back, and takes as long" do
    @attempt.send_reply(messages(:it_chat), "r3")

    assert_equal %w[ send_reply verify_sender ], @attempt.actions.last(2).map(&:kind)
    assert @attempt.sender_verified?(messages(:it_chat))
    assert_equal "The IT service desk says that isn't them.", @attempt.verification_reply(messages(:it_chat))
    assert_equal 2 + 1 + 5, @attempt.clock_minutes
  end

  test "checking after you've already called them back only costs the reply" do
    @attempt.verify_sender(messages(:it_chat))
    @attempt.send_reply(messages(:it_chat), "r3")

    assert_equal 2 + 5 + 1, @attempt.clock_minutes
    assert_equal 1, @attempt.actions.count(&:verify_sender?)
  end

  test "one reply per message, and only one of its own options" do
    assert_raises(ShiftAttempt::Rejected, match: /isn't one of the replies/) { @attempt.send_reply(messages(:it_chat), "r9") }
    assert_raises(ShiftAttempt::Rejected, match: /isn't one of the replies/) { @attempt.send_reply(messages(:it_chat), nil) }

    @attempt.send_reply(messages(:it_chat), "r2")
    assert_raises(ShiftAttempt::Rejected, match: /already replied/) { @attempt.send_reply(messages(:it_chat), "r1") }
  end

  test "a check that won't fit in the time left sends nothing" do
    @attempt.update!(clock_minutes: 25)

    assert_raises(ShiftAttempt::Rejected, match: /takes 6 min and you have 5/) { @attempt.send_reply(messages(:it_chat), "r3") }
    assert_not @attempt.reload.replied?(messages(:it_chat))
  end

  test "you can't reply to a reported message" do
    @attempt.report(messages(:it_chat))

    assert_raises(ShiftAttempt::Rejected, match: /already reported/) { @attempt.send_reply(messages(:it_chat), "r2") }
  end
end
