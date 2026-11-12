class ShiftAttemptsController < ApplicationController
  include ShiftAttemptScoped
  skip_before_action :set_attempt, only: :create
  rate_limit to: 20, within: 1.minute, only: :create,
    with: -> { redirect_to tracks_path, alert: "You're starting shifts too quickly. Try again in a minute." }

  # Starts a shift, or resumes the one already in progress.
  def create
    shift = Shift.published.find_by!(slug: params[:shift_id])
    redirect_to ShiftAttempt.start(user: Current.user, shift:)
  end

  def show
  end
end
