# A themed run of missions within a path, played in order. unlock_after is how many missions on the
# track before must be finished for this one to open (User::Unlocks).
#
# A daily track is the pool the Intercept of the day is drawn from (DailyIntercept): it's not listed on
# the paths page, has no unlock rule of its own and doesn't count towards a path's progress.
class Track < ApplicationRecord
  belongs_to :path

  enum :difficulty, { beginner: "beginner", intermediate: "intermediate", advanced: "advanced" }, validate: true

  has_many :missions, -> { order(:position) }, dependent: :destroy

  scope :published, -> { where(published: true) }
  scope :ordered, -> { order(:position) }
  scope :listed, -> { where(daily: false) }

  validates :slug, presence: true, uniqueness: true
  validates :title, :description, presence: true
  validates :unlock_after, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  def to_param
    slug
  end
end
