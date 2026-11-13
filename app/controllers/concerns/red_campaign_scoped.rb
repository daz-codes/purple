# Finds the campaign named by the URL's token. Only its owner can see or act on it: anyone else gets a
# 404, so tokens can't be probed.
module RedCampaignScoped
  extend ActiveSupport::Concern

  included do
    before_action :set_campaign
  end

  private
    def set_campaign
      @campaign = Current.user.red_campaigns.includes(target: { options: :technique }).find_by!(token: params[:red_campaign_token] || params[:token])
    end
end
