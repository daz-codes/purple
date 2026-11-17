class MissionAttemptsController < ApplicationController
  include MissionAttemptScoped
  skip_before_action :set_attempt, only: %i[ new create ]
  rate_limit to: 20, within: 1.minute, only: :create,
    with: -> { redirect_to paths_path, alert: "You're starting missions too quickly. Try again in a minute." }

  # Requires sign-in, so "Sign in to play" on a briefing brings the player back to it afterwards.
  def new
    redirect_to mission_path(params[:mission_id])
  end

  # Starts a mission, or resumes the one already in progress.
  def create
    mission = Mission.published.find_by!(slug: params[:mission_id])
    redirect_to MissionAttempt.start(user: Current.user, mission:)
  end

  def show
  end
end
