# Preview at http://localhost:3000/rails/mailers/email_confirmations_mailer/confirm
class EmailConfirmationsMailerPreview < ActionMailer::Preview
  def confirm
    EmailConfirmationsMailer.confirm(User.take)
  end
end
