class PagesController < ApplicationController
  allow_unauthenticated_access

  # Signed-in players get their dashboard; everyone else gets the introduction.
  def home
    return unless authenticated?

    @user = Current.user
    @open_attempt = @user.mission_attempts.open.includes(:mission).order(:started_at).last
    @draft_campaign = @user.red_campaigns.draft.includes(:target).order(:created_at).last
    @next_mission = Mission.in_play_order.merge(Track.listed).includes(track: { path: { tracks: :missions } })
      .where.not(id: @user.mission_attempts.finished.select(:mission_id)).find { |mission| unlocks.open?(mission) }
    @daily = Mission::DailyIntercept.new
    @next_target = Target.published.in_order.where.not(id: @user.red_campaigns.launched.select(:target_id)).first
    @badges = Badge.ordered
    @earned = @user.user_badges.index_by(&:badge_id)
    render :dashboard
  end

  def privacy
  end

  def terms
  end
end
