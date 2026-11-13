# A tell-tale sign in a phishing message that Blue can flag for bonus points.
#
# A red flag is either a whole part of the message (anchor: from, reply_to, to, subject, or an
# importer-assigned l1/a1), or a quoted phrase in the body: the quote's paragraph anchor (p1) and
# where the quote starts and ends in that paragraph's text.
#
# A red flag can also contradict something an earlier, genuine message said: contradicts_key names
# that message and contradicts_quote its words ("We'll never email you about your password"), so the
# debrief can show the two side by side.
class RedFlag < ApplicationRecord
  WHOLE_ANCHOR = /\A(from|reply_to|to|subject|[la]\d+)\z/
  PARAGRAPH_ANCHOR = Message::Paragraph::BLOCK_ANCHOR

  belongs_to :message

  validates :key, presence: true, uniqueness: { scope: :message_id }
  validates :label, :explanation, presence: true
  validates :points, numericality: { only_integer: true, greater_than: 0 }
  validates :anchor, format: { with: WHOLE_ANCHOR }, unless: :quote?
  validates :anchor, format: { with: PARAGRAPH_ANCHOR }, if: :quote?

  # The genuine message whose words this red flag contradicts. Debrief only.
  def contradicted_message
    message.shift.messages.find_by(key: contradicts_key) if contradicts_key
  end

  # A quoted red flag is found by a highlight that covers enough of it (Message::Paragraph#finds_quote?).
  def found_by?(flag)
    return flag.whole? && flag.anchor == anchor unless quote?
    return false unless flag.text? && flag.anchor == anchor

    !!message.paragraphs[anchor]&.finds_quote?(flag.from, flag.to, quote_start, quote_end)
  end
end
