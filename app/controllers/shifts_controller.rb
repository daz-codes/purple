# The briefing before a shift starts.
class ShiftsController < ApplicationController
  allow_unauthenticated_access

  def show
    @shift = Shift.published.includes(:track, :tasks).find_by!(slug: params[:id])
    @open_attempt = Current.user.shift_attempts.open.find_by(shift: @shift) if authenticated?
  end
end
