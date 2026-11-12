# Flagging the parts of a message that look wrong: the sender, the subject, a paragraph, a link or
# an attachment. Every part the player can see can be flagged, and flagging takes no time, so a flag
# gives nothing away: whether it was right waits for the debrief. Flagging a part again takes the flag off.
module ShiftAttempt::Flaggable
  extend ActiveSupport::Concern

  # For each action in order: true if it put a flag on, false if it took one off, nil if it isn't a
  # flag at all. Flagging the same part of the same message again toggles it. The one place that
  # rule lives.
  def self.toggles(actions)
    standing = Set.new
    actions.map do |action|
      next unless action.flag_element?

      key = [ action.target_key, action.result["anchor"] ]
      standing.add?(key) ? true : (standing.delete(key) && false)
    end
  end

  # The anchors still flagged after a run of actions on one message.
  def self.standing_anchors(actions)
    actions.zip(toggles(actions)).each_with_object({}) do |(action, on), state|
      state[action.result["anchor"]] = on unless on.nil?
    end.select { |_, on| on }.keys
  end

  def flag(message, anchor)
    acting_on(message) do
      anchor = anchor.to_s
      reject "There's nothing to flag there." unless flaggable?(message, anchor)

      record :flag_element, message:, result: { "anchor" => anchor }
    end
  end

  def flagged_anchors(message)
    ShiftAttempt::Flaggable.standing_anchors(actions.select { |action| action.target_key == message.key })
  end

  private
    # Only parts the player can see: To and Reply-To appear once the full headers are expanded.
    def flaggable?(message, anchor)
      message.anchors.include?(anchor) &&
        (!anchor.in?(Message::EXPANDED_HEADER_ANCHORS) || headers_expanded?(message))
    end
end
