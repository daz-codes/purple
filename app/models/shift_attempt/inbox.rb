# The messages the player can see: those that have arrived (see ShiftAttempt::Arrivals) and haven't
# been dealt with yet. The browser only ever knows a message by its #message_ref.
#
# Messages that arrive together are shown in an order shuffled per attempt, so a replay isn't a
# memory test.
module ShiftAttempt::Inbox
  extend ActiveSupport::Concern

  class_methods do
    def message_ref_secret
      @message_ref_secret ||= Rails.application.key_generator.generate_key("shift_attempt/message_ref", 32)
    end
  end

  def arrivals
    @arrivals ||= ShiftAttempt::Arrivals.new(shift.messages.to_a, actions)
  end

  # Messages that have arrived so far, newest first, as a mail client shows them. The ones there from
  # the start come last, in this attempt's shuffled order.
  def arrived_messages
    @arrived_messages ||= begin
      at_start, later = arrivals.messages.partition(&:arrives_at_start?)
      order = shuffled_positions
      later.reverse + at_start.sort_by { |message| order.fetch(message.position, 0) }
    end
  end

  def inbox_messages
    arrived_messages.reject { |message| handled?(message) }
  end

  def reported_messages
    arrived_messages.select { |message| reported?(message) }
  end

  def archived_messages
    arrived_messages.select { |message| archived?(message) }
  end

  def handled?(message)
    reported?(message) || archived?(message)
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

  def reload(*)
    @arrivals = @arrived_messages = nil
    super
  end

  private
    # Each message's place in this attempt's shuffled order, seeded from the token.
    def shuffled_positions
      seed = Digest::SHA256.hexdigest(token).first(8).to_i(16)
      shift.messages.map(&:position).shuffle(random: Random.new(seed)).each_with_index.to_h
    end
end
