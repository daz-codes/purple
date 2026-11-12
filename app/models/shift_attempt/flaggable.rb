# Flagging the parts of a message that look wrong: the sender, the subject, a paragraph, a link or
# an attachment. Every part can be flagged and flagging is free, so a flag gives nothing away: whether
# it was right waits for the debrief. Flagging a part again takes the flag off.
module ShiftAttempt::Flaggable
  extend ActiveSupport::Concern

  # The anchors still flagged after a run of flag_element actions on one message: each action
  # toggles its anchor.
  def self.standing_anchors(actions)
    actions.select(&:flag_element?).map { |action| action.result["anchor"] }.tally.select { |_, count| count.odd? }.keys
  end

  def flag(message, anchor)
    acting_on(message) do
      anchor = anchor.to_s
      reject "There's nothing to flag there." unless message.anchors.include?(anchor)

      record :flag_element, message:, result: { "anchor" => anchor }
    end
  end

  def flagged_anchors(message)
    ShiftAttempt::Flaggable.standing_anchors(actions.select { |action| action.target_key == message.key })
  end
end
