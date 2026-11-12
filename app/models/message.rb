# An email, SMS or chat message in a shift.
#
# SECRET: legit, links' outcomes and tasks, red flags, techniques and attachment outcomes are
# answers. They must never reach the browser before the debrief.
class Message < ApplicationRecord
  enum :channel, { email: "email", sms: "sms", chat: "chat" }, validate: true

  belongs_to :shift
  has_many :links, -> { order(:id) }, dependent: :destroy
  has_many :red_flags, -> { order(:id) }, dependent: :destroy
  has_many :message_techniques, dependent: :destroy
  has_many :techniques, through: :message_techniques

  validates :key, presence: true, uniqueness: { scope: :shift_id }
  validates :from_name, :from_address, :body_html, presence: true
  validates :legit, inclusion: { in: [ true, false ] }
  validates :position, numericality: { only_integer: true }
  validates :arrives_at_minute, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  PUBLIC_REF_FORMAT = /\Am(\d+)\z/

  def self.find_by_public_ref(ref)
    position = ref.to_s[PUBLIC_REF_FORMAT, 1]
    find_by(position: position.to_i) if position
  end

  def phish?
    !legit?
  end

  # The only identifier the browser sees. Keys are authored and descriptive ("fake_invoice"), so
  # they'd give the answer away; the position in the shift doesn't.
  def public_ref
    "m#{position}"
  end

  # Attachment details that are safe to show. Each attachment's outcome stays on the server.
  def visible_attachments
    attachments.map { |attachment| attachment.slice("id", "name", "type", "size") }
  end
end
