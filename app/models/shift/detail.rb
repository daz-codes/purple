# One private detail the player can hand over: on their persona card (staff number, memorable word…),
# the live MFA code, or something learned from a message (a payment codeword quoted in its text).
#
# SECRET: a detail's sensitivity, and whether a message needs or wants it, are answers. They stay on
# the server until the debrief. Learned details' keys are descriptive (wire_codeword), so the browser
# only ever sees them as the notes the player saved.
#
#   public:   anyone may have it (name, role)
#   internal: genuine colleagues and systems that need it, by reply or on a portal
#   secret:   only the genuine system that needs it, on its portal page; never in a message
#   never:    nobody, except the sign-in page that asked for it (the MFA code)
class Shift::Detail
  SENSITIVITIES = %w[ public internal secret never ].freeze

  # What sharing each above-public detail with the wrong person costs (a phish), and with the right
  # person who didn't need it (oversharing to a genuine message).
  LEAK_POINTS = { "internal" => -20, "secret" => -50, "never" => -50 }.freeze
  OVERSHARE_POINTS = { "internal" => -5, "secret" => -15 }.freeze

  attr_reader :key, :label, :sensitivity, :red_use, :message_key, :anchor, :quote, :quote_start, :quote_end

  def initialize(key:, label:, sensitivity:, red_use: nil, message_key: nil, anchor: nil, quote: nil, quote_start: nil, quote_end: nil)
    @key, @label, @sensitivity, @red_use = key, label, sensitivity, red_use
    @message_key, @anchor, @quote, @quote_start, @quote_end = message_key, anchor, quote, quote_start, quote_end
  end

  # The persona card's details, with what Red could do with each one (for "What Red now knows").
  CARD = [
    [ "name", "Your name", "public", nil ],
    [ "role", "Your role", "public", nil ],
    [ "staff_number", "Staff number", "internal", "quote it to HR or the service desk to pass as you" ],
    [ "extension", "Desk extension", "internal", "call colleagues as if from your desk, and sound like an insider" ],
    [ "memorable_word", "Memorable word", "secret", "pass the IT phone line's security check as you and have your password reset" ],
    [ "security_answer", "Security answer", "secret", "answer your account's security question and take it over" ],
    [ "mfa_code", "MFA code", "never", "sign in as you, straight past your second factor" ]
  ].map { |key, label, sensitivity, red_use| new(key:, label:, sensitivity:, red_use:) }.freeze

  CARD_KEYS = CARD.map(&:key).freeze

  # A detail learned from a message, as the importer stores it on the message.
  def self.learned(message_key, stored)
    new(key: stored["key"], label: stored["label"], sensitivity: stored["sensitivity"], red_use: stored["red_use"],
      message_key:, anchor: stored["anchor"], quote: stored["quote"], quote_start: stored["quote_start"], quote_end: stored["quote_end"])
  end

  def self.card(key)
    CARD.find { |detail| detail.key == key.to_s }
  end

  def card?
    message_key.nil?
  end

  def learned?
    !card?
  end

  def above_public?
    sensitivity != "public"
  end

  # Secrets and the MFA code only ever belong on a genuine page that asks for them, never in a message.
  def page_only?
    sensitivity.in?(%w[ secret never ])
  end

  def ==(other)
    other.is_a?(Shift::Detail) && other.key == key
  end
  alias eql? ==

  def hash
    key.hash
  end
end
