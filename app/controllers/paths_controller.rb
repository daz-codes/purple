class PathsController < ApplicationController
  allow_unauthenticated_access

  def index
    @paths = Path.published.ordered.includes(:opens_after_path, tracks: :missions)
    @daily = DailyIntercept.new
  end
end
