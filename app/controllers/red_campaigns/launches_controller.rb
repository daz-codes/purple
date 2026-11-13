# Launching the campaign at the bots. The results page replays what happened.
class RedCampaigns::LaunchesController < ApplicationController
  include WorkshopPlay

  def create
    @campaign.launch
    redirect_to @campaign, status: :see_other
  end
end
