# Answering a text or chat with one of the canned replies it offers. There's no free text, so a
# reply can only ever be one the content author wrote. Each message takes one reply.
#
# What a reply leads to is decided on the server, by its hidden outcome:
#   safe:       a fine answer. For a genuine message that expects a reply, this is what it wanted.
#   poor:       an answer to a genuine message that doesn't do what it asked, so it doesn't count.
#   compromise: the player handed a phisher what they asked for, such as a one-time code. It counts
#               like entering a password on a bait page.
#   verify:     the player checks with someone they already trust first, and gets the message's
#               verify_result. Like a call-back, it adds 30 seconds to the attempt's time.
# The player only ever sees the reply's text and the answers that come back.
#
# The send_reply action keeps a copy of the reply as it was sent (its text, outcome, response and any
# check), so re-importing the content later can't change what an old attempt did or scored.
module ShiftAttempt::Replyable
  extend ActiveSupport::Concern

  # The reply sent to each message, by message key, as stored on its send_reply action.
  def self.sent(actions)
    actions.select(&:send_reply?).to_h { |action| [ action.target_key, action.result ] }
  end

  # Whether a sent reply handed over what the sender asked for.
  def self.gave_in?(reply)
    reply&.dig("outcome") == "compromise"
  end

  def send_reply(message, reply_id)
    acting_on(message) do
      reply = message.reply(reply_id.to_s) or reject "That isn't one of the replies you can send."
      reject "You've already replied to that." if replied?(message)

      result = reply.slice("id", "text", "outcome", "response")
      checks = reply["outcome"] == "verify"
      result["check"] = message.verify_result.presence || ShiftAttempt::Verifiable::NO_ANSWER if checks
      record :send_reply, message:, result:, penalty: checks ? ShiftAttempt::Timed::CALL_PENALTY : 0
    end
  end

  def replied?(message)
    done?(:send_reply, message.key)
  end

  # The reply the player sent, as they saw it: its text, the answer that came back and, if they checked
  # first, what the person they trust said. Never its outcome.
  def sent_reply(message)
    ShiftAttempt::Replyable.sent(actions)[message.key]&.slice("text", "response", "check")
  end
end
