# Calling the sender back on a number you already hold. Their answer is scripted per message. The call
# is instant on screen, but adds 30 seconds to the attempt's time.
module ShiftAttempt::Verifiable
  extend ActiveSupport::Concern

  NO_ANSWER = "Nobody picked up.".freeze

  def verify_sender(message)
    acting_on(message) do
      reject "You've already checked with the sender." if sender_verified?(message)

      record :verify_sender, message:, penalty: ShiftAttempt::Timed::CALL_PENALTY,
        result: { "reply" => message.verify_result.presence || NO_ANSWER }
    end
  end

  def sender_verified?(message)
    done?(:verify_sender, message.key)
  end

  def verification_reply(message)
    actions.find { |action| action.verify_sender? && action.target_key == message.key }&.result&.dig("reply")
  end
end
