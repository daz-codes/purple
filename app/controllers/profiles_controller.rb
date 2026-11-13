# A player's public profile: both sides' levels, their preferred side, and their badges.
class ProfilesController < ApplicationController
  allow_unauthenticated_access

  def show
    @user = User.find_by!(display_name: params[:display_name])
    @badges = @user.user_badges.includes(:badge).order(:awarded_at).map(&:badge)
  end
end
