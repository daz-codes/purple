# A tell-tale sign in a phishing message that Blue can flag for bonus points.
# The anchor is a neutral id: from, reply_to, to, subject, or an importer-assigned p1/l1/a1.
class RedFlag < ApplicationRecord
  ANCHOR_FORMAT = /\A(from|reply_to|to|subject|[pla]\d+)\z/

  belongs_to :message

  validates :key, presence: true, uniqueness: { scope: :message_id }
  validates :label, :explanation, presence: true
  validates :anchor, format: { with: ANCHOR_FORMAT }
  validates :points, numericality: { only_integer: true, greater_than: 0 }
end
