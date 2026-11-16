# The email ErrorAlert sends when production reports an error. Plain text only.
class ErrorAlertsMailer < ApplicationMailer
  def alert(to:, error_class:, message:, backtrace:, handled:, source:, context_keys:, occurred_at:)
    @error_class = error_class
    @message = message
    @backtrace = backtrace
    @handled = handled
    @source = source
    @context_keys = context_keys
    @occurred_at = occurred_at

    mail to:, subject: "[Purple] #{error_class}: #{message.truncate(80)}" do |format|
      format.text
    end
  end
end
