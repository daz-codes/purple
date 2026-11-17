# A themed run of missions within a path, played in order. unlock_after is how many missions on the
# track before must be finished for this one to open (enforced from P1).
class Track < ApplicationRecord
  belongs_to :path

  enum :difficulty, { beginner: "beginner", intermediate: "intermediate", advanced: "advanced" }, validate: true

  has_many :missions, -> { order(:position) }, dependent: :destroy

  scope :published, -> { where(published: true) }
  scope :ordered, -> { order(:position) }

  validates :slug, presence: true, uniqueness: true
  validates :title, :description, presence: true
  validates :unlock_after, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  def to_param
    slug
  end
end
