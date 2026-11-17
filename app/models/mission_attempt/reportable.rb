# Reporting a message to the security team removes it from the inbox, like archiving it. Whether that
# was right is only revealed when the mission is scored.
module MissionAttempt::Reportable
  extend ActiveSupport::Concern

  def report(message)
    acting_on(message) { record :report_message, message: }
  end

  def reported?(message)
    done?(:report_message, message.key)
  end
end
