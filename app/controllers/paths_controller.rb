class PathsController < ApplicationController
  allow_unauthenticated_access

  def index
    @paths = Path.published.ordered.includes(tracks: :missions)
    @finished_mission_ids = authenticated? ? Current.user.mission_attempts.finished.distinct.pluck(:mission_id).to_set : Set.new
  end
end
