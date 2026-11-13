# Which messages have arrived in an attempt, and when, worked out from the action log. A pure
# function of the shift's messages and the actions, like the Scorecard.
#
# A message arrives at the start, once a number of messages have been dealt with (arrives_after_handled),
# or once one particular message has (arrives_after). Dealing with a message means reporting or
# archiving it. Only *that* a message was dealt with counts, never whether it was handled right, so an
# arrival never says anything about the player's choices.
class ShiftAttempt::Arrivals
  # wave: 0 for the messages there at the start, then 1, 2… for each message dealt with that brought
  # new ones. Messages in the same wave arrived together.
  Arrival = Data.define(:message, :at_seconds, :wave)

  # The keys of every message that would arrive if the player dealt with everything that arrived:
  # what the importer checks, so no message is stranded.
  def self.reachable(messages)
    arrived = messages.select(&:arrives_at_start?)
    loop do
      handled = arrived.map(&:key)
      more = (messages - arrived).select { |message| triggered?(message, handled) }
      return arrived.map(&:key) if more.empty?

      arrived += more
    end
  end

  def self.triggered?(message, handled_keys)
    if message.arrives_after_handled
      handled_keys.size >= message.arrives_after_handled
    elsif message.arrives_after
      handled_keys.include?(message.arrives_after)
    else
      true
    end
  end

  def initialize(messages, actions)
    @messages = messages
    @actions = actions
  end

  # Every arrival so far, in the order they arrived.
  def all
    @all ||= begin
      arrivals = @messages.select(&:arrives_at_start?).map { |message| Arrival.new(message:, at_seconds: 0, wave: 0) }
      handled = []
      @actions.each do |action|
        next unless action.handling?
        next if handled.include?(action.target_key) || arrivals.none? { |arrival| arrival.message.key == action.target_key }

        handled << action.target_key
        arrived = arrivals.map(&:message)
        wave = handled.size
        (@messages - arrived).select { |message| self.class.triggered?(message, handled) }.each do |message|
          arrivals << Arrival.new(message:, at_seconds: action.at_seconds + action.penalty_seconds, wave:)
        end
      end
      arrivals
    end
  end

  def messages
    all.map(&:message)
  end

  def at_seconds(message)
    all.find { |arrival| arrival.message == message }&.at_seconds
  end
end
