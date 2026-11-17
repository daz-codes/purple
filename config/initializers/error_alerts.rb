# Email the team about errors reported to Rails.error (unhandled exceptions in requests and jobs,
# and anything reported explicitly). Only switched on where ERROR_ALERTS_TO is set, which
# config/deploy.yml does for production. See ErrorAlert.
Rails.application.config.after_initialize do
  if (recipients = ENV["ERROR_ALERTS_TO"]).present?
    Rails.error.subscribe(ErrorAlert.new(to: recipients))
  end
end
