# The briefing before a shift starts.
class ShiftsController < ApplicationController
  allow_unauthenticated_access

  def show
    @shift = Shift.published.includes(:track, :tasks).find_by!(slug: params[:id])
    if authenticated?
      @open_attempt = Current.user.shift_attempts.open.find_by(shift: @shift)
    else
      # "Sign in to play" brings the player back to this briefing.
      session[:return_to_after_authenticating] = request.url
    end
  end
end
