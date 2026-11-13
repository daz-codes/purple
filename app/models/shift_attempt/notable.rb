# Saving words from a message as a note, to share later (a payment codeword, a supplier's name). The
# player highlights words, or clicks a sentence, in "save to notes" mode; saving exactly the same words
# again takes the note off.
#
# Any words can be saved and it takes no time, so a note gives nothing away: whether it matches a detail
# the shift cares about is worked out privately, and only matters when it's shared.
module ShiftAttempt::Notable
  extend ActiveSupport::Concern

  # anchor: a sentence (p1s2), or a paragraph (p1) with from and to, the highlighted range in its text.
  def save_note(message, anchor, from: nil, to: nil)
    acting_on(message) do
      flag = flag_for(message, anchor.to_s, from, to)
      reject "Save words from the message's text." unless flag&.text?

      paragraph = message.paragraphs[flag.anchor]
      record :save_note, message:, result: flag.to_result.merge("text" => paragraph.excerpt(flag.from, flag.to))
    end
  end

  # The notes still saved, oldest first.
  def notes
    @notes ||= actions.select(&:save_note?).each_with_index.each_with_object({}) do |(action, index), standing|
      note = ShiftAttempt::Note.from_action(action, number: index + 1)
      key = [ note.message_key, *note.range ]
      standing.key?(key) ? standing.delete(key) : standing[key] = note
    end.values
  end

  def notes_on(message)
    notes.select { |note| note.message_key == message.key }
  end

  def reload(*)
    @notes = nil
    super
  end
end
