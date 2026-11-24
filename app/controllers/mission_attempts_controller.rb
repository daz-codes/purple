class MissionAttemptsController < ApplicationController
  include MissionAttemptScoped
  skip_before_action :set_attempt, only: %i[ new create ]
  rate_limit to: 20, within: 1.minute, only: :create,
    with: -> { redirect_to paths_path, alert: "You're starting missions too quickly. Try again in a minute." }

  # Requires sign-in, so "Sign in to play" on a briefing brings the player back to it afterwards.
  def new
    redirect_to mission_path(params[:mission_id])
  end

  # Starts a mission, or resumes the one already in progress. A locked mission can't be started, however
  # the request got here.
  def create
    mission = Mission.playable.find_by!(slug: params[:mission_id])
    return redirect_to(mission, alert: unlocks.opens_when(mission.track)) unless unlocks.open?(mission)

    redirect_to MissionAttempt.start(user: Current.user, mission:)
  end

  # A signals mission shows one intercept at a time: the one named in the URL, or the first still open.
  def show
    return unless @attempt.open? && @attempt.mission.kind_signals?

    @intercept = @attempt.find_intercept(params[:intercept]) ||
      @attempt.intercepts.find { |intercept| !@attempt.closed?(intercept) } || @attempt.intercepts.first
  end
end
