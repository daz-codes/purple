# Answering a text or chat with one of the canned replies it offers. There's no free text, so a
# reply can only ever be one the content author wrote. Each message takes one reply.
#
# What a reply leads to is decided on the server, by its hidden outcome:
#   safe:       nothing happens beyond the conversation.
#   compromise: the player handed over what the sender asked for, such as a one-time code. It counts
#               like entering a password on a bait page.
#   verify:     the player checks with someone they already trust before doing anything, which is
#               the same move as calling the sender back, and takes as long.
# The player only ever sees the reply's text and the answer that comes back.
module ShiftAttempt::Replyable
  extend ActiveSupport::Concern

  OUTCOMES = %w[ safe compromise verify ].freeze

  def send_reply(message, reply_id)
    acting_on(message) do
      reply = message.reply(reply_id.to_s) or reject "That isn't one of the replies you can send."
      reject "You've already replied to that." if replied?(message)

      checks = reply["outcome"] == "verify" && !sender_verified?(message)
      cost = action_cost(:send_reply) + (checks ? action_cost(:verify_sender) : 0)
      reject "Not enough time left: that takes #{cost} min and you have #{minutes_left}." unless affordable?(cost)

      record :send_reply, message:, result: { "reply" => reply["id"] }
      record :verify_sender, message:, result: { "reply" => message.verify_result.presence || ShiftAttempt::Verifiable::NO_ANSWER } if checks
    end
  end

  def replied?(message)
    done?(:send_reply, message.key)
  end

  # Whether the reply the player sent handed over what the sender asked for. Only asked once it's sent,
  # to show the damage, as a password entered on a bait page does.
  def handed_over?(message)
    chosen_reply(message)&.fetch("outcome") == "compromise"
  end

  # The reply the player sent, as they saw it: its text and the answer that came back.
  def sent_reply(message)
    chosen_reply(message)&.slice("text", "response")
  end

  private
    def chosen_reply(message)
      action = actions.find { |action| action.send_reply? && action.target_key == message.key }
      message.reply(action.result["reply"]) if action
    end
end
