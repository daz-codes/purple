class RedCampaignsController < ApplicationController
  include RedCampaignScoped
  skip_before_action :set_campaign, only: :create
  rate_limit to: 20, within: 1.minute, only: :create,
    with: -> { redirect_to targets_path, alert: "You're starting campaigns too quickly. Try again in a minute." }

  # Starts a campaign, or resumes the draft already in progress.
  def create
    target = Target.published.find_by!(slug: params[:target_id])
    redirect_to RedCampaign.start(user: Current.user, target:)
  end

  def show
  end
end
