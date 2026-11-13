# Answering a text or chat with one of the canned replies it offers. There's no free text, so a
# reply can only ever be one the content author wrote. Each message takes one reply.
#
# What a reply leads to is decided on the server, by its hidden outcome:
#   safe:       nothing happens beyond the conversation.
#   compromise: the player handed over what the sender asked for, such as a one-time code. It counts
#               like entering a password on a bait page.
#   verify:     the player says they'll check with someone they already trust, and does: they get the
#               message's verify_result, as a call-back would. It's still one reply and costs what every
#               reply costs, since a different price would give away which reply it is.
# The player only ever sees the reply's text and the answers that come back.
#
# The send_reply action keeps a copy of the reply as it was sent (its text, outcome, response and any
# check), so re-importing the content later can't change what an old attempt did or scored.
module ShiftAttempt::Replyable
  extend ActiveSupport::Concern

  OUTCOMES = %w[ safe compromise verify ].freeze

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
      result["check"] = message.verify_result.presence || ShiftAttempt::Verifiable::NO_ANSWER if reply["outcome"] == "verify"
      record :send_reply, message:, result:
    end
  end

  def replied?(message)
    done?(:send_reply, message.key)
  end

  # Whether the reply the player sent handed over what the sender asked for. Only asked once it's sent,
  # to show the damage, as a password entered on a bait page does.
  def handed_over?(message)
    ShiftAttempt::Replyable.gave_in?(ShiftAttempt::Replyable.sent(actions)[message.key])
  end

  # The reply the player sent, as they saw it: its text, the answer that came back and, if they checked
  # first, what the person they trust said. Never its outcome.
  def sent_reply(message)
    ShiftAttempt::Replyable.sent(actions)[message.key]&.slice("text", "response", "check")
  end
end
