# The score for a signals mission, worked out from its action log, like MissionAttempt::Scorecard: a pure
# function of the mission's content and the actions, shown only once the mission is over.
#
# - A solved intercept is worth its points, less WRONG_ANSWER for each wrong answer before it, but
#   never less than half its points: finding the flag always counts for more than the guesses cost.
# - An intercept left unsolved scores nothing.
# - Each hint takes its penalty_percent of the maximum off the total.
#
# There's no speed bonus: puzzles reward care, not haste. Stars use the same thresholds as an inbox, and
# a perfect run (every flag first time, no hints) always earns three.
class MissionAttempt::InterceptScorecard
  WRONG_ANSWER = -10

  HintUsed = MissionAttempt::Scorecard::HintUsed

  # One intercept's result: what the player submitted, in order, and what it scored.
  class InterceptResult
    attr_reader :intercept, :submissions

    def initialize(intercept, submissions)
      @intercept = intercept
      @submissions = submissions
    end

    def solved? = submissions.any? { |action| action.result["correct"] }
    def wrong_answers = submissions.take_while { |action| !action.result["correct"] }.size
    def best_points = intercept.points

    def points
      return 0 unless solved?

      [ best_points + wrong_answers * WRONG_ANSWER, (best_points / 2.0).ceil ].max
    end
  end

  attr_reader :elapsed_seconds

  def initialize(mission:, actions:, elapsed_seconds: nil, cleared: false, relaxed: false)
    @mission = mission
    @actions = actions
    @elapsed_seconds = elapsed_seconds
    @cleared = cleared
    @relaxed = relaxed
  end

  def mission = @mission
  def relaxed? = @relaxed
  def cleared? = @cleared

  def intercepts
    @intercepts ||= @mission.intercepts.map do |intercept|
      InterceptResult.new(intercept, @actions.select { |action| action.submit_flag? && action.target_key == intercept.key })
    end
  end

  def intercept_points
    intercepts.sum(&:points)
  end

  def speed_bonus = 0

  def total
    [ intercept_points - hint_penalty, 0 ].max
  end

  def total_max
    intercepts.sum(&:best_points)
  end

  def best_possible = total_max

  def hints
    @hints ||= @actions.select(&:use_hint?).filter_map do |action|
      hint = @mission.hints.find { |candidate| candidate.position == action.result["hint"] } or next
      HintUsed.new(hint:, penalty: (total_max * hint.penalty_percent / 100.0).round)
    end
  end

  def hint_penalty
    hints.sum(&:penalty)
  end

  def flags_found
    intercepts.count(&:solved?)
  end

  def perfect?
    intercepts.all? { |result| result.points == result.best_points } && hints.none?
  end

  # Nothing to fall for in a puzzle.
  def compromised? = false

  # 0 to 3, on the inbox's thresholds.
  def stars
    return 3 if perfect?
    return 0 unless total_max.positive?

    MissionAttempt::Scorecard::STAR_THRESHOLDS.count { |threshold| total >= total_max * threshold }
  end
end
