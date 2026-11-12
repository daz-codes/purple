# Reporting a message to the security team removes it from the inbox. Whether that was right is
# only revealed when the shift is scored.
module ShiftAttempt::Reportable
  extend ActiveSupport::Concern

  def report(message)
    acting_on(message) { record :report_message, message: }
  end

  def reported?(message)
    done?(:report_message, message.key)
  end
end
