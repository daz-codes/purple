class EmailConfirmationsMailer < ApplicationMailer
  def confirm(user)
    @user = user
    @token = user.email_confirmation_token
    mail subject: "Confirm your email address for Purple", to: user.email_address
  end
end
