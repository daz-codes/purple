# Picking a card for a slot (or taking it back).
class RedCampaigns::ChoicesController < ApplicationController
  include WorkshopPlay

  def create
    build { @campaign.choose(option) }
  end

  def destroy
    build { @campaign.unchoose(option) }
  end

  private
    def option
      @campaign.target.options.find { |option| option.id.to_s == params[:option_id].to_s } or
        raise RedCampaign::Rejected, "That card isn't for this target."
    end
end
