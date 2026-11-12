# An email, SMS or chat message in a shift.
#
# SECRET: legit, links' outcomes and tasks, red flags, techniques, attachment outcomes and reply
# outcomes are answers. They must never reach the browser before the debrief.
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

  def phish?
    !legit?
  end

  # The parts of the message a player can flag, by their neutral ids: the headers, then every
  # paragraph, link and attachment. Everything is flaggable, so this says nothing about which parts
  # are red flags.
  #
  # The importer checks red flags against this list too, so the two can't disagree.
  def anchors
    @anchors ||= [ "from", ("to" if to_address.present?), ("reply_to" if reply_to.present?), ("subject" if subject.present?) ].compact +
      Nokogiri::HTML5.fragment(body_html).css("[data-anchor]").map { |node| node["data-anchor"] } +
      attachments.map { |attachment| attachment["id"] }
  end

  # Header anchors only shown once the player has expanded the full headers.
  EXPANDED_HEADER_ANCHORS = %w[ to reply_to ].freeze

  def attachment(id)
    attachments.find { |attachment| attachment["id"] == id } if id
  end

  # Attachment details that are safe to show. Each attachment's outcome stays on the server.
  def visible_attachments
    attachments.map { |attachment| attachment.slice("id", "name", "type", "size") }
  end

  # The canned replies a text or chat message offers, by their neutral ids (r1, r2…).
  def reply(id)
    replies.find { |reply| reply["id"] == id } if id
  end

  # Reply options that are safe to show: only their text. What each one leads to stays on the server.
  def visible_replies
    replies.map { |reply| reply.slice("id", "text") }
  end
end
