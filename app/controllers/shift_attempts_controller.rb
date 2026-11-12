class ShiftAttemptsController < ApplicationController
  include ShiftAttemptScoped
  skip_before_action :set_attempt, only: %i[ new create ]
  rate_limit to: 20, within: 1.minute, only: :create,
    with: -> { redirect_to tracks_path, alert: "You're starting shifts too quickly. Try again in a minute." }

  # Requires sign-in, so "Sign in to play" on a briefing brings the player back to it afterwards.
  def new
    redirect_to shift_path(params[:shift_id])
  end

  # Starts a shift, or resumes the one already in progress.
  def create
    shift = Shift.published.find_by!(slug: params[:shift_id])
    redirect_to ShiftAttempt.start(user: Current.user, shift:)
  end

  def show
  end
end
