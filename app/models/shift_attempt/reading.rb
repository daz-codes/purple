# Opening messages. Reading is free, and the last message opened is the one in the reading pane.
module ShiftAttempt::Reading
  extend ActiveSupport::Concern

  def read(message)
    acting_on(message) { record :open_message, message: }
  end

  def opened?(message)
    done?(:open_message, message.key)
  end

  # The message in the reading pane: the last one opened, unless it has since been dealt with.
  def current_message
    return @current_message if defined?(@current_message)

    key = actions.reverse_each.find(&:open_message?)&.target_key
    message = arrived_messages.find { |arrived| arrived.key == key } if key
    @current_message = message unless message.nil? || handled?(message)
  end

  def reload(*)
    remove_instance_variable(:@current_message) if defined?(@current_message)
    super
  end
end
