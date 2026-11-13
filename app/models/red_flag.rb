# A tell-tale sign in a phishing message that Blue can flag for bonus points.
#
# A red flag is either a whole part of the message (anchor: from, reply_to, to, subject, or an
# importer-assigned l1/a1), or a quoted phrase in the body: the quote's paragraph anchor (p1) and
# where the quote starts and ends in that paragraph's text.
class RedFlag < ApplicationRecord
  WHOLE_ANCHOR = /\A(from|reply_to|to|subject|[la]\d+)\z/
  PARAGRAPH_ANCHOR = Message::Paragraph::BLOCK_ANCHOR

  # A highlight finds a quoted red flag if it covers at least this much of the quote, and either stays
  # within one sentence or isn't much longer than the quote: highlighting a whole paragraph to catch
  # everything in it doesn't count.
  MIN_COVERAGE = 0.5
  LENGTH_SLACK = 20

  belongs_to :message

  validates :key, presence: true, uniqueness: { scope: :message_id }
  validates :label, :explanation, presence: true
  validates :points, numericality: { only_integer: true, greater_than: 0 }
  validates :anchor, format: { with: WHOLE_ANCHOR }, unless: :quote?
  validates :anchor, format: { with: PARAGRAPH_ANCHOR }, if: :quote?

  def found_by?(flag)
    return flag.whole? && flag.anchor == anchor unless quote?
    return false unless flag.text? && flag.anchor == anchor

    covered = [ flag.to, quote_end ].min - [ flag.from, quote_start ].max
    return false if covered < (quote_end - quote_start) * MIN_COVERAGE

    flag.length <= 2 * (quote_end - quote_start) + LENGTH_SLACK ||
      message.paragraphs[anchor]&.within_one_sentence?(flag.from, flag.to)
  end
end
