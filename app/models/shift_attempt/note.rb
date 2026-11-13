# Words the player saved from a message, to share later: a chip labelled with the words. id is neutral
# ("n" and the id of the action that saved it), so it says nothing about what the note matches.
ShiftAttempt::Note = Data.define(:id, :message_key, :anchor, :from, :to, :text) do
  def self.from_action(action)
    new(id: "n#{action.id}", message_key: action.target_key, anchor: action.result["anchor"],
      from: action.result["from"], to: action.result["to"], text: action.result["text"])
  end

  def range
    [ anchor, from, to ]
  end

  # The detail these words are, if any: a detail quoted in the same message that the highlight covers
  # well enough (the red-flag rules). SECRET until the debrief.
  def detail_in(message)
    paragraph = message&.paragraphs&.[](anchor) or return
    message.learned_details.find do |detail|
      detail.anchor == anchor && paragraph.finds_quote?(from, to, detail.quote_start, detail.quote_end)
    end
  end
end
