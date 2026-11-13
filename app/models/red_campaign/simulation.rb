# Runs a campaign's email past each Blue bot. A pure function of the chosen cards, the bots and a
# seed: the same inputs always give the same results, so a launched campaign can be replayed and the
# balance rules tested.
#
# Each bot reads the email first. For the sender, the pretext and the timing in turn, it may spot the
# technique; if it does, that's what gave it away, and it either reports the email (more likely the
# more vigilant it is) or checks with the sender first. If nothing in the email gives it away, it
# clicks, and may still spot the lure or the payload and back out: a near miss. Otherwise it's fooled.
#
# The chance of spotting a technique grows with the bot's vigilance and its detects bonus for that
# technique, and shrinks with the technique's stealth. A pretext that fits what the target is really
# expecting (its relevance, 0-3) makes everything in the email less likely to be spotted. Every
# chance stays between 5% and 90%, so nothing is ever certain.
class RedCampaign::Simulation
  Result = Data.define(:bot, :outcome, :gave_away) do
    def fooled? = outcome == :fooled
    def near_miss? = outcome == :near_miss
  end

  EMAIL_STAGE = %w[ sender pretext timing ].freeze
  CLICK_STAGE = %w[ lure payload ].freeze
  BASE = 0.1
  VIGILANCE_WEIGHT = 0.06
  STEALTH_WEIGHT = 0.04
  RELEVANCE_DAMPING = 0.15
  MIN_CHANCE = 0.05
  MAX_CHANCE = 0.9

  def initialize(options:, bots:, seed:)
    @options = options.index_by(&:category)
    @bots = bots
    @seed = seed
  end

  def results
    @results ||= begin
      random = Random.new(@seed)
      @bots.map { |bot| judge(bot, random) }
    end
  end

  # The chance a bot spots one card's technique, from 0 to 1.
  def chance(bot, option)
    technique = option.technique
    chance = BASE + (bot.vigilance + bot.detection_bonus(technique.key)) * VIGILANCE_WEIGHT - technique.stealth * STEALTH_WEIGHT
    chance *= 1 - RELEVANCE_DAMPING * relevance if option.category.in?(EMAIL_STAGE)
    chance.clamp(MIN_CHANCE, MAX_CHANCE)
  end

  private
    def judge(bot, random)
      EMAIL_STAGE.each do |category|
        option = @options[category] or next
        next unless random.rand < chance(bot, option)

        outcome = random.rand < bot.vigilance / 10.0 ? :reported : :verified
        return Result.new(bot:, outcome:, gave_away: option)
      end

      CLICK_STAGE.each do |category|
        option = @options[category] or next
        return Result.new(bot:, outcome: :near_miss, gave_away: option) if random.rand < chance(bot, option)
      end

      Result.new(bot:, outcome: :fooled, gave_away: nil)
    end

    def relevance
      @options["pretext"]&.relevance.to_i
    end
end
