class Track < ApplicationRecord
  enum :difficulty, { beginner: "beginner", intermediate: "intermediate", advanced: "advanced" }, validate: true

  has_many :shifts, -> { order(:position) }, dependent: :destroy

  scope :published, -> { where(published: true) }
  scope :ordered, -> { order(:position) }

  validates :slug, presence: true, uniqueness: true
  validates :title, :description, presence: true

  def to_param
    slug
  end
end
