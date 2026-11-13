require "test_helper"

# Site visit: Sam's text (needs a reply) is there at the start; the fake IT chat arrives once one
# message has been dealt with.
class ShiftAttempt::ReplyableTest < ActiveSupport::TestCase
  setup do
    @attempt = ShiftAttempt.start(user: users(:one), shift: shifts(:site_visit))
  end

  test "sending a reply keeps a copy of it, and shows the player only what they said and what came back" do
    @attempt.send_reply(messages(:sam_text), "r1")

    action = @attempt.actions.last
    assert_equal [ "send_reply", "sam_text", 0 ], [ action.kind, action.target_key, action.penalty_seconds ]
    assert_equal({ "id" => "r1", "text" => "Sure, see you there", "outcome" => "safe", "response" => "Legend, thanks!" }, action.result)
    assert @attempt.replied?(messages(:sam_text))
    assert_equal({ "text" => "Sure, see you there", "response" => "Legend, thanks!" }, @attempt.sent_reply(messages(:sam_text)))
    assert @attempt.open?, "replying doesn't deal with the message: archiving does"
  end

  test "checking with the service desk gets the trusted answer and, like a call-back, adds 30 seconds" do
    bring_the_chat
    @attempt.send_reply(messages(:it_chat), "r3")

    assert_equal 30, @attempt.actions.last.penalty_seconds
    assert_equal "The IT service desk says that isn't them.", @attempt.sent_reply(messages(:it_chat))["check"]
    assert_not @attempt.sender_verified?(messages(:it_chat)), "it isn't calling the sender back"
  end

  test "a reply's score doesn't change when the content is re-imported" do
    bring_the_chat
    @attempt.send_reply(messages(:it_chat), "r1")
    messages(:it_chat).update!(replies: messages(:it_chat).replies.reverse.each_with_index.map { |reply, i| reply.merge("id" => "r#{i + 1}") })

    attempt = ShiftAttempt.find(@attempt.id)
    assert_equal "Here it is: 482 913", attempt.sent_reply(messages(:it_chat))["text"]
    assert attempt.scorecard.message_result_for("it_chat").gave_in?
  end

  test "one reply per message, and only one of its own options" do
    assert_raises(ShiftAttempt::Rejected, match: /isn't one of the replies/) { @attempt.send_reply(messages(:sam_text), "r9") }
    assert_raises(ShiftAttempt::Rejected, match: /isn't one of the replies/) { @attempt.send_reply(messages(:sam_text), nil) }

    @attempt.send_reply(messages(:sam_text), "r2")
    assert_raises(ShiftAttempt::Rejected, match: /already replied/) { @attempt.send_reply(messages(:sam_text), "r1") }
  end

  test "you can't reply to a message you've dealt with" do
    @attempt.archive(messages(:sam_text))

    assert_raises(ShiftAttempt::Rejected, match: /already dealt with/) { @attempt.send_reply(messages(:sam_text), "r1") }
  end

  private
    def bring_the_chat
      @attempt.send_reply(messages(:sam_text), "r1")
      @attempt.archive(messages(:sam_text))
    end
end
