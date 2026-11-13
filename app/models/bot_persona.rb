# A simulated Blue player who judges Red's email in the Workshop. vigilance (1-10) is how carefully
# they read; detects adjusts that for particular techniques (technique key => bonus, which can be
# negative: Nia is new and won't question someone senior).
class BotPersona < ApplicationRecord
  validates :key, presence: true, uniqueness: true
  validates :name, :description, presence: true
  validates :vigilance, numericality: { only_integer: true, in: 1..10 }
  validate :detects_are_integers

  scope :in_order, -> { order(:position, :id) }

  def detection_bonus(technique_key)
    detects.fetch(technique_key.to_s, 0)
  end

  private
    def detects_are_integers
      errors.add(:detects, "must map technique keys to whole numbers") unless detects.is_a?(Hash) && detects.values.all?(Integer)
    end
end
