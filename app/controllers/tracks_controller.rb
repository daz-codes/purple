class TracksController < ApplicationController
  allow_unauthenticated_access

  def index
    @tracks = Track.published.ordered.includes(:shifts)
  end

  def show
    @track = Track.published.find_by!(slug: params[:id])
    @shifts = @track.shifts.published
  end
end
