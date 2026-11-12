# The messages the player can see: those whose arrival minute the clock has reached. The browser
# only ever knows a message by its #message_ref.
module ShiftAttempt::Inbox
  extend ActiveSupport::Concern

  class_methods do
    def message_ref_secret
      @message_ref_secret ||= Rails.application.key_generator.generate_key("shift_attempt/message_ref", 32)
    end
  end

  # Messages that have landed so far, newest first, as a mail client shows them.
  def arrived_messages
    @arrived_messages ||= shift.messages.where(arrives_at_minute: ..clock_minutes)
      .reorder(arrives_at_minute: :desc, position: :desc).to_a
  end

  def inbox_messages
    arrived_messages.reject { |message| reported?(message) }
  end

  def reported_messages
    arrived_messages.select { |message| reported?(message) }
  end

  # Authored keys are descriptive ("fake_invoice") and positions change when content is re-imported,
  # so the ref is an HMAC of the attempt's token and the message's key: opaque, stable for the whole
  # attempt, and different in every attempt, so players can't share "m3 is the phish".
  def message_ref(message)
    OpenSSL::HMAC.hexdigest("SHA256", self.class.message_ref_secret, "#{token}:#{message.key}").first(16)
  end

  def find_arrived_message(ref)
    ref = ref.to_s
    arrived_messages.find { |message| ActiveSupport::SecurityUtils.secure_compare(message_ref(message), ref) }
  end

  def next_arrival_minute
    shift.messages.where(arrives_at_minute: (clock_minutes + 1)..).minimum(:arrives_at_minute)
  end

  # Lets time pass until the next message arrives.
  def wait_for_mail
    acting_on do
      next_arrival = next_arrival_minute or reject "Nothing else is due today. End the shift when you're ready."

      record :wait, cost: next_arrival - clock_minutes
    end
  end

  # Once nothing is left on the task list, the rest of the day's mail arrives at once: the clock
  # jumps to the last arrival, so the player still has to deal with everything before the shift can
  # end. Moving the clock, rather than delivering mail early, keeps every arrival time true.
  def deliver_remaining_mail
    last_arrival = shift.messages.maximum(:arrives_at_minute)
    return unless last_arrival && last_arrival > clock_minutes

    record :wait, cost: [ last_arrival, time_budget ].min - clock_minutes, result: { "tasks_done" => true }
  end

  def reload(*)
    @arrived_messages = nil
    super
  end
end
