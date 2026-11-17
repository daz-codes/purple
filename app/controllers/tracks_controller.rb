class TracksController < ApplicationController
  allow_unauthenticated_access

  def index
    @tracks = Track.published.ordered.includes(:missions)
  end

  def show
    @track = Track.published.find_by!(slug: params[:id])
    @missions = @track.missions.published
    @best_attempts = authenticated? ? Current.user.mission_attempts.best_by_mission(@missions) : {}
  end
end
