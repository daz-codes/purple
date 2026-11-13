class PagesController < ApplicationController
  allow_unauthenticated_access

  # Signed-in players get their dashboard; everyone else gets the introduction.
  def home
    return unless authenticated?

    @user = Current.user
    @open_attempt = @user.shift_attempts.open.includes(:shift).order(:started_at).last
    @draft_campaign = @user.red_campaigns.draft.includes(:target).order(:created_at).last
    @next_shift = Shift.published.joins(:track).merge(Track.published).order("tracks.position, shifts.position")
      .where.not(id: @user.shift_attempts.finished.select(:shift_id)).first
    @next_target = Target.published.in_order.where.not(id: @user.red_campaigns.launched.select(:target_id)).first
    @badges = Badge.ordered
    @earned = @user.user_badges.index_by(&:badge_id)
    render :dashboard
  end
end
