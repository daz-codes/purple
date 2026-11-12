# The development mailbox at /letter_opener shows each email in an iframe and keeps the email's own
# inline styles, which the app's strict CSP would block. It only exists in development, so it alone
# goes without a CSP.
if Rails.env.development?
  Rails.application.config.to_prepare do
    LetterOpenerWeb::ApplicationController.content_security_policy false
  end
end
