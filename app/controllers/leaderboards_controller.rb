# The leaderboards: Blue, Red or overall; this week or all time; timed or relaxed play.
class LeaderboardsController < ApplicationController
  allow_unauthenticated_access

  def show
    @leaderboard = Leaderboard.new(side: params[:side], period: params[:period], relaxed: params[:relaxed])
    @mine = @leaderboard.entry_for(Current.user) if authenticated?
  end
end
