# Archiving a message: the player is done with it, whether that meant replying, doing something on its
# portal page, or nothing at all. It leaves the inbox. Whether it needed more than archiving is only
# revealed in the debrief.
module ShiftAttempt::Archivable
  extend ActiveSupport::Concern

  def archive(message)
    acting_on(message) { record :archive_message, message: }
  end

  def archived?(message)
    done?(:archive_message, message.key)
  end
end
