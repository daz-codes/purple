require "test_helper"

class RedCampaign::SimulationTest < ActiveSupport::TestCase
  setup do
    @bots = BotPersona.in_order.to_a
    @cheap = target_options(:overdue, :spoof, :link, :sign_in, :friday)
  end

  test "the same cards, bots and seed always give the same results" do
    first = simulate(@cheap, seed: 42).map { |result| [ result.bot.key, result.outcome, result.gave_away&.key ] }

    assert_equal first, simulate(@cheap, seed: 42).map { |result| [ result.bot.key, result.outcome, result.gave_away&.key ] }
    assert_operator (1..50).map { |seed| simulate(@cheap, seed:).map(&:outcome) }.uniq.size, :>, 1, "different seeds play out differently"
  end

  test "the chance of spotting a card grows with vigilance and detection, shrinks with stealth, and stays between 5% and 90%" do
    bob, carol = @bots
    simulation = RedCampaign::Simulation.new(options: @cheap, bots: @bots, seed: 1)

    assert_operator simulation.chance(carol, target_options(:spoof)), :>, simulation.chance(bob, target_options(:spoof))
    assert_operator simulation.chance(carol, target_options(:spoof)), :>, simulation.chance(carol, target_options(:lookalike)), "stealthier"
    assert_equal 0.05, simulation.chance(bob, target_options(:friday)), "Bob, late on a Friday: the floor"
    assert @bots.product(@cheap).all? { |bot, option| simulation.chance(bot, option).between?(0.05, 0.9) }
  end

  test "a relevant pretext makes the email itself harder to spot" do
    generic = RedCampaign::Simulation.new(options: @cheap, bots: @bots, seed: 1)
    relevant = RedCampaign::Simulation.new(options: target_options(:bank_change, :spoof, :link, :sign_in, :friday), bots: @bots, seed: 1)
    carol = @bots.last

    assert_operator relevant.chance(carol, target_options(:spoof)), :<, generic.chance(carol, target_options(:spoof))
    assert_equal relevant.chance(carol, target_options(:link)), generic.chance(carol, target_options(:link)), "the lure is judged on its own"
  end

  test "each bot is fooled, backs out of the page, or spots the email and reports it or checks first, naming what gave it away" do
    outcomes = (1..300).flat_map { |seed| simulate(@cheap, seed:) }

    assert_equal %i[ fooled near_miss reported verified ], outcomes.map(&:outcome).uniq.sort
    outcomes.each do |result|
      if result.fooled?
        assert_nil result.gave_away
      elsif result.near_miss?
        assert_includes %w[ lure payload ], result.gave_away.category
      else
        assert_includes %w[ sender pretext timing ], result.gave_away.category
      end
    end
  end

  private
    def simulate(options, seed:)
      RedCampaign::Simulation.new(options:, bots: @bots, seed:).results
    end
end
