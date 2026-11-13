# An email, SMS or chat message in a shift.
#
# Each message arrives at the start of the shift, once a number of messages have been dealt with
# (arrives_after_handled), or once one particular message has (arrives_after: its key). A genuine
# message expects something: a reply, an action on its portal page, or just archiving, and is worth
# its points when handled that way. urgent_within_minutes, if set, is how soon after it arrives it
# must be handled for full points.
#
# SECRET: legit, expects, points, urgency, links' outcomes, red flags, techniques, attachment outcomes
# and reply outcomes are answers. They must never reach the browser before the debrief. So are the
# arrival triggers: they'd tell the player how many messages are still to come.
class Message < ApplicationRecord
  enum :channel, { email: "email", sms: "sms", chat: "chat" }, validate: true
  enum :expects, { reply: "reply", act: "act", archive: "archive" }, prefix: true, validate: { allow_nil: true }

  belongs_to :shift
  has_many :links, -> { order(:id) }, dependent: :destroy
  has_many :red_flags, -> { order(:id) }, dependent: :destroy
  has_many :message_techniques, dependent: :destroy
  has_many :techniques, through: :message_techniques

  validates :key, presence: true, uniqueness: { scope: :shift_id }
  validates :from_name, :from_address, :body_html, presence: true
  validates :legit, inclusion: { in: [ true, false ] }
  validates :position, numericality: { only_integer: true }
  validates :points, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :expects, presence: true, if: :legit?
  validates :expects, absence: true, unless: :legit?

  def phish?
    !legit?
  end

  def arrives_at_start?
    arrives_after_handled.nil? && arrives_after.nil?
  end

  # The parts of the message a player can flag as a whole, by their neutral ids: the headers, then
  # every link and attachment. Text is flagged by highlighting within a paragraph (see #paragraphs).
  # Everything is flaggable, so this says nothing about which parts are red flags. A text or chat on
  # the phone shows only its sender and body.
  #
  # The importer checks red flags against these too, so the two can't disagree.
  def whole_anchors
    @whole_anchors ||= header_anchors +
      Nokogiri::HTML5.fragment(body_html).css("[data-anchor]").map { |node| node["data-anchor"] }.grep(/\Al\d+\z/) +
      attachments.map { |attachment| attachment["id"] }
  end

  def header_anchors
    return [ "from" ] unless email?

    [ "from", ("to" if to_address.present?), ("reply_to" if reply_to.present?), ("subject" if subject.present?) ].compact
  end

  # The body's text blocks, by anchor (p1, p2…).
  def paragraphs
    @paragraphs ||= Message::Paragraph.all_in(body_html).index_by(&:anchor)
  end

  # The paragraph a block or sentence anchor (p2, p2s1) belongs to.
  def paragraph_for(anchor)
    paragraphs[anchor.to_s[/\Ap\d+/]]
  end

  def link(key)
    links.find { |link| link.key == key }
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
