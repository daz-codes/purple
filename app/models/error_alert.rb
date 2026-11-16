# A subscriber to Rails' error reporter (Rails.error) that emails the team when something breaks in
# production. It's registered in config/initializers/error_alerts.rb only when ERROR_ALERTS_TO is set.
#
# - Only errors with severity :error alert; handled warnings and info don't.
# - Each kind of error (its class and where it was raised) alerts at most once an hour, so a broken
#   page hit a thousand times sends one email.
# - The email holds the error class, message and the app's own backtrace lines, never request
#   parameters or context values (they can hold players' details).
# - It never raises: a failure to send is logged and swallowed, so reporting can't cause more errors.
class ErrorAlert
  QUIET_FOR = 1.hour
  BACKTRACE_LINES = 15

  def initialize(to:, cache: Rails.cache, logger: Rails.logger)
    @to = to
    @cache = cache
    @logger = logger
  end

  def report(error, handled:, severity:, context:, source: nil)
    return unless severity == :error && @to.present?
    return unless first_in_a_while?(error)

    ErrorAlertsMailer.alert(to: @to, **summary(error, handled:, source:, context:)).deliver_now
  rescue StandardError => alert_error
    @logger.error "[ErrorAlert] couldn't send an alert for #{error.class}: #{alert_error.class}: #{alert_error.message}"
  end

  private
    def first_in_a_while?(error)
      @cache.write("error_alert/#{fingerprint(error)}", true, expires_in: QUIET_FOR, unless_exist: true)
    end

    def fingerprint(error)
      Digest::SHA256.hexdigest([ error.class.name, app_backtrace(error).first ].join("|"))
    end

    def summary(error, handled:, source:, context:)
      {
        error_class: error.class.name,
        message: error.message.to_s.truncate(500),
        backtrace: app_backtrace(error).first(BACKTRACE_LINES),
        handled:,
        source:,
        context_keys: context.keys.map(&:to_s).sort,
        occurred_at: Time.current
      }
    end

    def app_backtrace(error)
      Rails.backtrace_cleaner.clean(Array(error.backtrace))
    end
end
