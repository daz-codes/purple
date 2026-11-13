# Shared by the controllers for moves in the Workshop. Each makes its move inside #build; the response
# re-renders the builder by Turbo Stream. A move that isn't allowed changes nothing and says why.
module WorkshopPlay
  extend ActiveSupport::Concern

  included do
    include RedCampaignScoped

    rate_limit to: 120, within: 1.minute, with: -> { refuse "You're clicking too fast. Wait a moment and try again." }
    rescue_from RedCampaign::Rejected, with: ->(rejection) { refuse rejection.message }
  end

  private
    def build
      yield
      respond_to do |format|
        format.turbo_stream { render turbo_stream: turbo_stream.replace("campaign_builder", partial: "red_campaigns/builder", locals: { campaign: @campaign }) }
        format.html { redirect_to @campaign }
      end
    end

    def refuse(message)
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.update("campaign_notice", partial: "shift_attempts/notice", locals: { message:, alert: true }),
            status: :unprocessable_content
        end
        format.html { redirect_to @campaign, alert: message }
      end
    end
end
