# Finds the attempt named by the URL's token. Only its owner can see or act on it: anyone else
# gets a 404, so tokens can't be probed. An attempt left open too long is closed on the way in.
module MissionAttemptScoped
  extend ActiveSupport::Concern

  included do
    before_action :set_attempt
  end

  private
    def set_attempt
      @attempt = Current.user.mission_attempts.includes(mission: :track).find_by!(token: params[:mission_attempt_token] || params[:token])
      @attempt.expire_if_stale
    end
end
