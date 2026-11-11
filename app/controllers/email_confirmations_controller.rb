# The emailed link opens a page with a "Confirm" button rather than confirming
# on GET, so email link scanners can't confirm an address on the user's behalf.
class EmailConfirmationsController < ApplicationController
  allow_unauthenticated_access only: %i[ show update ]
  rate_limit to: 3, within: 10.minutes, only: :create,
    with: -> { redirect_back_or_to root_path, alert: "Please wait a few minutes before asking for another email." }

  before_action :set_user_by_token, only: %i[ show update ]

  def show
  end

  def update
    @user.confirm!
    redirect_to(authenticated? ? root_path : new_session_path, notice: "Thanks, your email address is confirmed.")
  end

  # Resend the confirmation email to the signed-in user.
  def create
    if Current.user.confirmed?
      redirect_back_or_to root_path, notice: "Your email address is already confirmed."
    else
      EmailConfirmationsMailer.confirm(Current.user).deliver_later
      redirect_back_or_to root_path, notice: "We've sent you a new confirmation email."
    end
  end

  private
    def set_user_by_token
      @user = User.find_by_email_confirmation_token(params[:token])
      redirect_to root_path, alert: "That confirmation link is invalid, has expired or has already been used." unless @user
    end
end
