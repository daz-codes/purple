# Finds a message in the attempt's inbox by its opaque ref. A message that hasn't arrived (or doesn't
# exist) is rejected like any other move that isn't allowed.
module ShiftAttemptMessageScoped
  extend ActiveSupport::Concern

  included do
    before_action :set_message
  end

  private
    def set_message
      @message = @attempt.find_arrived_message(params[:message_ref]) or
        raise ShiftAttempt::Rejected, "That message isn't in your inbox."
    end
end
