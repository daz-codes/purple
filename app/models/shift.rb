# One playable round for Blue: an inbox (or a phone) full of messages to deal with. par_minutes is
# the target time for the speed bonus.
# For the MVP every shift is authored by the system playing Red.
class Shift < ApplicationRecord
  enum :kind, { inbox: "inbox", messages: "messages" }, prefix: true, validate: true
  enum :difficulty, { beginner: "beginner", intermediate: "intermediate", advanced: "advanced" }, validate: true
  enum :author_side, { red: "red" }, prefix: :authored_by, validate: true
  enum :author_type, { system: "system", player: "player" }, prefix: :authored_by, validate: true

  belongs_to :track
  has_many :messages, -> { order(:position) }, dependent: :destroy
  has_many :hints, -> { order(:position) }, dependent: :destroy
  has_many :shift_attempts, dependent: :restrict_with_exception

  scope :published, -> { where(published: true) }

  validates :slug, presence: true, uniqueness: true
  validates :title, :briefing, :learning_summary, presence: true
  validates :par_minutes, numericality: { only_integer: true, greater_than: 0 }

  def to_param
    slug
  end

  # Every private detail in play: the persona card's, then those learned from messages (Shift::Detail).
  def details
    Shift::Detail::CARD + messages.flat_map(&:learned_details)
  end

  def detail(key)
    details.find { |detail| detail.key == key.to_s }
  end

  # Whether any message needs or wants a detail, so the details rules apply.
  def asks_for_details?
    messages.any? { |message| message.needs.any? || message.wants.any? }
  end
end
