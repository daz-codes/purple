require "test_helper"

# The balance rules from the plan (section 6b), checked against the shipped targets and bots.
class RedCampaign::BalanceTest < ActiveSupport::TestCase
  SEEDS = 0...300

  setup do
    Content::Import.new.run
    @bots = BotPersona.in_order.to_a
    @targets = Target.published.includes(options: :technique).to_a
  end

  test "there's a target for each of the three Blue shifts' companies" do
    assert_equal 3, @targets.size
    assert_equal 3, @targets.map(&:shift).uniq.size
  end

  test "no combination of cards fools every bot every time" do
    @targets.each do |target|
      affordable_sets(target).each do |cards|
        fooled_everyone = SEEDS.count { |seed| simulate(cards, seed:).all?(&:fooled?) }
        assert_operator fooled_everyone, :<, SEEDS.size / 2, "#{target.slug}: #{cards.map(&:key).join(", ")}"
      end
    end
  end

  test "a high-relevance pretext beats a generic one at equal cost" do
    @targets.each do |target|
      pretexts = target.options_for("pretext")
      relevant = pretexts.max_by(&:relevance)
      generic = pretexts.find { |pretext| pretext.cost == relevant.cost && pretext.relevance.zero? }
      assert generic, "#{target.slug} needs a generic pretext costing the same as its most relevant one"

      rest = (TargetOption::CATEGORIES - %w[ pretext ]).map { |category| target.options_for(category).min_by(&:cost) }
      assert_operator average_score(rest + [ relevant ]), :>, average_score(rest + [ generic ]), target.slug
    end
  end

  test "Careful Carol is rarely fooled by cheap, generic tricks" do
    carol = @bots.find { |bot| bot.key == "careful_carol" }

    @targets.each do |target|
      cheap = TargetOption::CATEGORIES.map do |category|
        target.options_for(category).select { |option| category != "pretext" || option.relevance.zero? }.min_by(&:cost)
      end
      fooled = SEEDS.count { |seed| RedCampaign::Simulation.new(options: cheap, bots: [ carol ], seed:).results.first.fooled? }
      assert_operator fooled, :<, SEEDS.size / 10, target.slug
    end
  end

  test "careful card choice beats spending as little as possible" do
    @targets.each do |target|
      cheapest = TargetOption::CATEGORIES.map { |category| target.options_for(category).min_by(&:cost) }
      best = affordable_sets(target).max_by { |cards| average_score(cards) + target.budget - cards.sum(&:cost) }

      assert_operator average_score(best) + target.budget - best.sum(&:cost), :>, average_score(cheapest) + target.budget - cheapest.sum(&:cost),
        target.slug
    end
  end

  private
    def affordable_sets(target)
      slots = TargetOption::CATEGORIES.map { |category| target.options_for(category) }
      slots.first.product(*slots.drop(1)).select { |cards| cards.sum(&:cost) <= target.budget }
    end

    def simulate(cards, seed:)
      RedCampaign::Simulation.new(options: cards, bots: @bots, seed:).results
    end

    def average_score(cards)
      SEEDS.sum { |seed| simulate(cards, seed:).sum { |result| result.fooled? ? 40 : result.near_miss? ? 15 : 0 } }.fdiv(SEEDS.size)
    end
end
