class ApplicationMailer < ActionMailer::Base
  default from: ENV.fetch("MAILER_FROM", "Purple <noreply@purple.example>")
  layout "mailer"
end
