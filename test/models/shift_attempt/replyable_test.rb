require "test_helper"

class ShiftAttempt::ReplyableTest < ActiveSupport::TestCase
  setup do
    @attempt = ShiftAttempt.start(user: users(:one), shift: shifts(:site_visit))
    @attempt.wait_for_mail
  end

  test "sending a reply keeps a copy of it, and shows the player only what they said and what came back" do
    @attempt.send_reply(messages(:sam_text), "r1")

    action = @attempt.actions.last
    assert_equal [ "send_reply", "sam_text", 1 ], [ action.kind, action.target_key, action.cost_minutes ]
    assert_equal({ "id" => "r1", "text" => "Sure, see you there", "outcome" => "safe", "response" => "Legend, thanks!" }, action.result)
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

  test "checking with the service desk is one reply, costs what every reply costs, and gets the trusted answer" do
    @attempt.send_reply(messages(:it_chat), "r3")

    assert_equal [ "send_reply" ], @attempt.actions.last(1).map(&:kind)
    assert_equal 2 + 1, @attempt.clock_minutes
    assert_equal "The IT service desk says that isn't them.", @attempt.sent_reply(messages(:it_chat))["check"]
    assert_not @attempt.sender_verified?(messages(:it_chat)), "it isn't calling the sender back"
  end

  test "a reply's score doesn't change when the content is re-imported" do
    @attempt.send_reply(messages(:it_chat), "r1")
    messages(:it_chat).update!(replies: messages(:it_chat).replies.reverse.each_with_index.map { |reply, i| reply.merge("id" => "r#{i + 1}") })

    attempt = ShiftAttempt.find(@attempt.id)
    assert attempt.handed_over?(messages(:it_chat))
    assert_equal "Here it is: 482 913", attempt.sent_reply(messages(:it_chat))["text"]
    assert_equal 50, attempt.scorecard.security_meter
  end

  test "one reply per message, and only one of its own options" do
    assert_raises(ShiftAttempt::Rejected, match: /isn't one of the replies/) { @attempt.send_reply(messages(:it_chat), "r9") }
    assert_raises(ShiftAttempt::Rejected, match: /isn't one of the replies/) { @attempt.send_reply(messages(:it_chat), nil) }

    @attempt.send_reply(messages(:it_chat), "r2")
    assert_raises(ShiftAttempt::Rejected, match: /already replied/) { @attempt.send_reply(messages(:it_chat), "r1") }
  end

  test "a reply that won't fit in the time left sends nothing" do
    @attempt.update!(clock_minutes: 30)

    assert_raises(ShiftAttempt::Rejected) { @attempt.send_reply(messages(:it_chat), "r3") }
    assert_not @attempt.reload.replied?(messages(:it_chat))
  end

  test "a reply that runs the clock out ends the shift with nothing logged after it" do
    @attempt.update!(clock_minutes: 29)
    @attempt.send_reply(messages(:it_chat), "r3")

    assert @attempt.reload.timed_out?
    assert_equal "send_reply", @attempt.actions.last.kind
  end

  test "you can't reply to a reported message" do
    @attempt.report(messages(:it_chat))

    assert_raises(ShiftAttempt::Rejected, match: /already reported/) { @attempt.send_reply(messages(:it_chat), "r2") }
  end
end
