# One flag the player put on a message: a whole part (the sender, a header, a link or an attachment),
# or a highlighted range of a paragraph's text. Sentence clicks are stored as the sentence's range, so
# a sentence and the same words dragged over are the same flag.
ShiftAttempt::Flag = Data.define(:anchor, :from, :to) do
  def self.from_result(result)
    new(anchor: result["anchor"], from: result["from"], to: result["to"])
  end

  def whole?
    from.nil?
  end

  def text?
    !whole?
  end

  def length
    to - from
  end

  def to_result
    { "anchor" => anchor, "from" => from, "to" => to }.compact
  end
end
