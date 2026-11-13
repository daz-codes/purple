# Who the player is for one attempt: the shift's name and role, and the private details generated for
# this attempt (staff number, desk extension, memorable word, and the answer to the shift's in-world
# security question). They're the player's own, so all of it is shown; nothing here says how sensitive
# a detail is or who may have it.
#
#   attempt.persona.staff_number # => "LH-48213"
#
# The values come from ShiftAttempt::Persona.generate, seeded from the attempt token, and are stored on
# the attempt, so changing the word lists later can't rewrite an old attempt.
class ShiftAttempt::Persona
  DETAILS = %w[ staff_number extension memorable_word security_answer ].freeze

  # Fictional, everyday words: nothing that could be someone's real memorable word by design, and no
  # brands. test/models/shift_attempt/identified_test.rb checks them against the fiction rules.
  ADJECTIVES = %w[ AMBER BRISK COPPER DUSKY EMBER FROSTY GINGER HAZEL INDIGO JUNIPER LUNAR MOSSY
                   NUTMEG OCHRE PEBBLE QUIET RUSTY SAFFRON TANGERINE VELVET WILLOW ].freeze
  NOUNS = %w[ BADGER COMET DRAGONFLY FALCON HEDGEHOG HERON KESTREL LANTERN MARMOT OTTER PUFFIN
              QUAIL RAVEN SPARROW TORTOISE WALRUS WREN ].freeze
  # Answers to name-type security questions ("Name of the Larkhill office dog?").
  NAMES = %w[ BISCUIT BRAMBLE CRUMPET DUMPLING FIGGY MAPLE MUFFIN NOODLE PEPPER PICKLE PUDDING
              SCONE TOFFEE TRUFFLE WAFFLE ].freeze

  def self.generate(shift:, seed:)
    random = Random.new(seed)
    prefix = shift.persona["staff_prefix"].presence || "ST"
    {
      "staff_number" => "#{prefix}-#{random.rand(10_000..99_999)}",
      "extension" => random.rand(2000..3999).to_s,
      "memorable_word" => "#{ADJECTIVES.sample(random:)} #{NOUNS.sample(random:)}",
      "security_answer" => NAMES.sample(random:)
    }
  end

  def initialize(shift:, details:)
    @profile = shift.persona
    @details = details
  end

  def present?
    @profile.present?
  end

  def name = @profile["name"]
  def role = @profile["role"]
  def security_question = @profile["security_question"]

  DETAILS.each do |detail|
    define_method(detail) { @details[detail] }
  end
end
