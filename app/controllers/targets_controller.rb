# Red's Workshop: the targets, and each one's recon brief.
class TargetsController < ApplicationController
  allow_unauthenticated_access

  def index
    @targets = Target.published.in_order.includes(:shift)
  end

  def show
    @target = Target.published.find_by!(slug: params[:id])
    @campaigns = authenticated? ? Current.user.red_campaigns.where(target: @target).order(created_at: :desc) : RedCampaign.none
  end
end
