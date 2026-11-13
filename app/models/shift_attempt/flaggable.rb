# Flagging the parts of a message that look wrong. A flag is either a whole part (the sender, a
# header, a link or an attachment) or some of the body's text: a sentence the player clicked, or words
# they highlighted. Text flags are stored as a character range in the paragraph's text (see
# Message::Paragraph), so a clicked sentence and the same words dragged over are the same flag.
#
# Every part and every word can be flagged, and flagging takes no time, so a flag gives nothing away:
# whether it was right waits for the debrief. Flagging exactly the same thing again takes it off.
module ShiftAttempt::Flaggable
  extend ActiveSupport::Concern

  # For each action in order: true if it put a flag on, false if it took one off, nil if it isn't a
  # flag at all. The one place the toggling rule lives.
  def self.toggles(actions)
    standing = Set.new
    actions.map do |action|
      next unless action.flag_element?

      key = [ action.target_key, ShiftAttempt::Flag.from_result(action.result) ]
      standing.add?(key) ? true : (standing.delete(key) && false)
    end
  end

  # The flags still standing after a run of actions on one message, in the order they were put on.
  def self.standing(actions)
    actions.zip(toggles(actions)).each_with_object({}) do |(action, on), state|
      next if on.nil?

      flag = ShiftAttempt::Flag.from_result(action.result)
      state.delete(flag)
      state[flag] = true if on
    end.keys
  end

  # anchor: a whole part (from, l1…), a sentence (p1s2), or a paragraph (p1) with from and to, the
  # highlighted range in its text.
  def flag(message, anchor, from: nil, to: nil)
    acting_on(message) do
      flag = flag_for(message, anchor.to_s, from, to) or reject "There's nothing to flag there."

      record :flag_element, message:, result: flag.to_result
    end
  end

  def flags_on(message)
    ShiftAttempt::Flaggable.standing(actions.select { |action| action.target_key == message.key })
  end

  private
    def flag_for(message, anchor, from, to)
      if message.whole_anchors.include?(anchor)
        ShiftAttempt::Flag.new(anchor:, from: nil, to: nil) if visible_part?(message, anchor)
      elsif anchor.match?(Message::Paragraph::SENTENCE_ANCHOR)
        paragraph = message.paragraph_for(anchor)
        sentence = paragraph&.sentence(anchor) or return
        text_flag(paragraph, sentence.from, sentence.to)
      elsif (paragraph = message.paragraphs[anchor])
        text_flag(paragraph, Integer(from, exception: false), Integer(to, exception: false))
      end
    end

    def text_flag(paragraph, from, to)
      from, to = paragraph.trim(from, to)
      ShiftAttempt::Flag.new(anchor: paragraph.anchor, from:, to:) if from
    end

    # To and Reply-To appear only once the full headers are expanded.
    def visible_part?(message, anchor)
      !anchor.in?(Message::EXPANDED_HEADER_ANCHORS) || headers_expanded?(message)
    end
end
