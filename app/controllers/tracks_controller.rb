class TracksController < ApplicationController
  allow_unauthenticated_access

  def show
    @track = Track.published.joins(:path).merge(Path.published).find_by!(slug: params[:id])
    @missions = @track.missions.published
    @best_attempts = authenticated? ? Current.user.mission_attempts.best_by_mission(@missions) : {}
  end
end
