# The briefing before a mission starts.
class MissionsController < ApplicationController
  allow_unauthenticated_access

  def show
    @mission = Mission.published.includes(:track).find_by!(slug: params[:id])
    @open_attempt = Current.user.mission_attempts.open.find_by(mission: @mission) if authenticated?
  end
end
