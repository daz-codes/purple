# Gives each attempt its own persona details when it starts (see ShiftAttempt::Persona), seeded from
# the attempt token and stored, so they stay the same for the whole attempt and its debrief and differ
# between attempts.
module ShiftAttempt::Identified
  extend ActiveSupport::Concern

  included do
    before_validation :generate_persona_details, on: :create
  end

  def persona
    @persona ||= ShiftAttempt::Persona.new(shift:, details: persona_details)
  end

  private
    def generate_persona_details
      return if persona_details.present? || shift.nil? || token.nil?

      secret = Rails.application.key_generator.generate_key("shift_attempt/persona", 32)
      seed = OpenSSL::HMAC.digest("SHA256", secret, token).unpack1("Q>")
      self.persona_details = ShiftAttempt::Persona.generate(shift:, seed:)
    end
end
