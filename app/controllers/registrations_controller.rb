class RegistrationsController < ApplicationController
  allow_unauthenticated_access
  rate_limit to: 5, within: 15.minutes, only: :create,
    with: -> { redirect_to new_registration_path, alert: "Too many sign-up attempts. Try again later." }

  before_action :redirect_signed_in_user

  def new
    @user = User.new
  end

  def create
    @user = User.new(registration_params)

    if @user.save
      start_new_session_for @user
      EmailConfirmationsMailer.confirm(@user).deliver_later
      redirect_to new_side_path, notice: "Welcome to Purple! Check your email to confirm your address."
    else
      render :new, status: :unprocessable_entity
    end
  end

  private
    def registration_params
      params.expect(user: %i[ email_address display_name password password_confirmation ])
    end
end
