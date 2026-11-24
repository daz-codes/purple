# /daily: today's Intercept of the day, by way of its briefing.
class DailyInterceptsController < ApplicationController
  allow_unauthenticated_access

  def show
    mission = DailyIntercept.new.mission or return redirect_to(paths_path, alert: "There's no Intercept of the day yet.")
    redirect_to mission
  end
end
