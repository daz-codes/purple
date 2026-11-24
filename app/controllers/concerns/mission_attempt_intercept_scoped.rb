# Finds the intercept named by the URL's opaque ref, in the attempt's own mission. Anything else is a 404.
module MissionAttemptInterceptScoped
  extend ActiveSupport::Concern

  included do
    before_action :set_intercept
  end

  private
    def set_intercept
      @intercept = @attempt.find_intercept(params[:intercept_ref]) or raise ActiveRecord::RecordNotFound
    end
end
