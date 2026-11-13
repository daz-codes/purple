# Launching a finished campaign: the email is assembled and stored, the bots judge it, and the result
# is scored and stored, so the debrief can replay it exactly even if the content changes later.
#
# Red scores 40 for each bot fooled, 15 for each that clicked but backed out (a near miss for them),
# nothing for reports or checks, and 1 for each unit of budget left: spending everything isn't optimal.
# Only a confirmed player's first launched campaign at each target is scored for XP (from M8).
module RedCampaign::Launchable
  extend ActiveSupport::Concern

  FOOLED = 40
  NEAR_MISS = 15
  STAR_THRESHOLDS = [ 0.3, 0.6, 0.9 ].freeze

  included do
    scope :scored, -> { where(scored: true) }
  end

  def launch
    with_lock do
      reject "This campaign has already been launched." unless draft?
      reject "Pick a card for every slot first: #{missing_slots.to_sentence} still empty." unless complete?

      email = RedCampaign::Email.new(chosen_options)
      simulation = RedCampaign::Simulation.new(options: chosen_options, bots: BotPersona.in_order.to_a, seed:)
      results = simulation.results.map do |result|
        { "bot" => result.bot.key, "outcome" => result.outcome.to_s, "gave_away" => result.gave_away&.technique&.key }
      end

      update!(status: :launched, launched_at: Time.current, results:,
        rendered_from: email.from, rendered_subject: email.subject, rendered_body_html: email.body_html,
        score: self.class.score_for(results, budget_left), scored: first_scored_campaign?)
    end
  end

  class_methods do
    def score_for(results, budget_left)
      results.sum { |result| { "fooled" => FOOLED, "near_miss" => NEAR_MISS }.fetch(result["outcome"], 0) } + budget_left
    end
  end

  # The best a campaign at this target could score: every bot fooled, and the budget left over from
  # the cheapest full set of cards.
  def max_score
    FOOLED * results.size + target.budget - cheapest_full_set
  end

  def stars
    return 0 unless launched?

    STAR_THRESHOLDS.count { |threshold| score >= max_score * threshold }
  end

  private
    def cheapest_full_set
      TargetOption::CATEGORIES.sum { |category| target.options_for(category).map(&:cost).min.to_i }
    end

    def first_scored_campaign?
      user.earns_xp? && !user.red_campaigns.scored.where.not(id:).exists?(target_id:)
    end
end
