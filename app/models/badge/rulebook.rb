# Which badges a player has earned, judged when they finish something. Each rule reads the player's
# record: the scorecard of the attempt they just finished, the campaign they just launched, their
# streak, and (for the cumulative and two-sided badges) their other attempts and campaigns.
#
# Rules only ever say a badge is earned; awarding it (once) is User::Badged's job.
class Badge::Rulebook
  RULES = {
    # Blue
    "first_catch" => :reported_a_phish?,
    "eagle_eye" => :found_every_red_flag_without_hints?,
    "clean_shift" => :three_star_shift?,
    "productive_paranoid" => :handled_everything_right?,
    "near_miss_ninja" => :three_near_misses?,
    "seven_day_streak" => :seven_day_streak?,
    # Red
    "fooled_carol" => :fooled_careful_carol?,
    "budget_hacker" => :three_stars_on_half_the_budget?,
    # Both
    "purple_belt" => :three_stars_on_both_sides?
  }.freeze

  NEAR_MISSES_FOR_NINJA = 3
  STREAK_FOR_BADGE = 7

  def initialize(user, source)
    @user = user
    @source = source
  end

  def earned_keys
    RULES.select { |_, rule| send(rule) }.keys
  end

  private
    def attempt = (@source if @source.is_a?(ShiftAttempt))
    def campaign = (@source if @source.is_a?(RedCampaign))

    def card
      @card ||= attempt&.scorecard
    end

    def reported_a_phish?
      card.present? && card.phishes.any?(&:reported?)
    end

    # Every red flag in every phish found, and no hints.
    def found_every_red_flag_without_hints?
      card.present? && card.phishes.any? && card.phishes.all? { |result| result.missed_flags.empty? } && card.hints.none?
    end

    def three_star_shift?
      card.present? && card.stars == 3
    end

    # Every genuine message handled as it needed, and every phish reported.
    def handled_everything_right?
      card.present? && card.genuine.all?(&:done?) && card.phishes.all?(&:reported?)
    end

    # Three bait pages or downloads closed before entering anything, across all the player's shifts.
    def three_near_misses?
      return false unless attempt

      @user.shift_attempts.finished.includes(:shift, :attempt_actions).sum { |finished| finished.scorecard.messages.sum { |result| result.near_misses.size } } >=
        NEAR_MISSES_FOR_NINJA
    end

    def seven_day_streak?
      @user.current_streak >= STREAK_FOR_BADGE
    end

    def fooled_careful_carol?
      campaign.present? && campaign.results.any? { |result| result["bot"] == "careful_carol" && result["outcome"] == "fooled" }
    end

    # Three stars with at least half the budget unspent.
    def three_stars_on_half_the_budget?
      campaign.present? && campaign.stars == 3 && campaign.budget_left * 2 >= campaign.total_budget
    end

    # Three stars on a shift and on the Workshop target that attacks the same company.
    def three_stars_on_both_sides?
      shift = attempt&.shift || campaign&.target&.shift or return false

      three_star_attempt = @user.shift_attempts.finished.where(shift:).includes(:attempt_actions).any? { |finished| finished.scorecard.stars == 3 }
      three_star_campaign = @user.red_campaigns.launched.joins(:target).where(targets: { shift_id: shift.id }).any? { |launched| launched.stars == 3 }
      three_star_attempt && three_star_campaign
    end
end
