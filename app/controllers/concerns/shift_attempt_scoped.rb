# Finds the attempt named by the URL's token. Only its owner can see or act on it: anyone else
# gets a 404, so tokens can't be probed.
module ShiftAttemptScoped
  extend ActiveSupport::Concern

  included do
    before_action :set_attempt
  end

  private
    def set_attempt
      token = params[:shift_attempt_token] || params[:token]
      @attempt = Current.user.shift_attempts.includes(shift: :track).find_by!(token:)
    end
end
