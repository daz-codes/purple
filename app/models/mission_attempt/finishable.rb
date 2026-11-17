# The end of a mission. It ends by itself once every message has been dealt with (the inbox is empty and
# nothing more is coming), when the player clocks off early, or when it's left open too long. Anything not
# dealt with by then counts as ignored. Finishing scores the attempt from its log.
module MissionAttempt::Finishable
  extend ActiveSupport::Concern

  included do
    scope :finished, -> { where.not(status: :open) }
    scope :scored, -> { where(scored: true) }
  end

  class_methods do
    # The highest-scoring finished attempt at each of the given missions, keyed by mission id: the
    # player's progress on a track page. Ties go to the earlier attempt.
    def best_by_mission(missions)
      finished.where(mission: missions)
        .select("DISTINCT ON (mission_attempts.mission_id) mission_attempts.*")
        .reorder(:mission_id, score: :desc, completed_at: :asc)
        .includes(:attempt_actions, :mission).index_by(&:mission_id)
    end
  end

  def finished?
    !open?
  end

  def stand_down
    acting_on do
      record :stand_down
      finish :stood_down
    end
  end

  # A finished attempt's scorecard is judged against the content captured when it finished, and can't
  # change, so it's built once (rebuilding the captured content is the expensive part).
  def scorecard
    return build_scorecard(mission) unless finished? && result_content.present?

    @finished_scorecard ||= build_scorecard(MissionAttempt::ContentSnapshot.new(result_content).mission)
  end

  def reload(*)
    @finished_scorecard = nil
    super
  end

  private
    def build_scorecard(content)
      MissionAttempt::Scorecard.new(mission: content, actions:, elapsed_seconds:, cleared: completed?, relaxed:)
    end

    def finish_if_cleared
      finish :completed if open? && inbox_messages.empty?
    end

    def finish(status)
      return if finished?

      self.status = status
      self.completed_at = Time.current
      self.result_content = MissionAttempt::ContentSnapshot.capture(mission)
      update! scored: !timed_out? && first_scored_attempt?, score: scorecard.total
    end

    # XP (from M8) is only for confirmed players' first finished attempt at each mission. One that expired
    # because the player walked away doesn't use it up.
    def first_scored_attempt?
      user.earns_xp? && !user.mission_attempts.scored.where.not(id:).exists?(mission_id:)
    end
end
