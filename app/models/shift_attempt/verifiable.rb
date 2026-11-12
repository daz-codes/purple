# Calling the sender back on a number you already hold. Their reply is scripted per message.
module ShiftAttempt::Verifiable
  extend ActiveSupport::Concern

  NO_ANSWER = "Nobody picked up.".freeze

  def verify_sender(message)
    acting_on(message) do
      reject "You've already checked with the sender." if sender_verified?(message)

      record :verify_sender, message:, result: { "reply" => message.verify_result.presence || NO_ANSWER }
    end
  end

  def sender_verified?(message)
    done?(:verify_sender, message.key)
  end

  def verification_reply(message)
    actions.find { |action| action.verify_sender? && action.target_key == message.key }&.result&.dig("reply")
  end
end
