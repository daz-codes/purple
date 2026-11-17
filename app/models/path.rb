# A skill area, such as Phishing or Codebreaking: a run of tracks played in order. Every path is
# listed from the start; one whose missions haven't been written yet shows as coming soon.
class Path < ApplicationRecord
  enum :opens, { always: "always", after_missions: "after_missions", after_first_track: "after_first_track" },
    prefix: true, validate: true

  belongs_to :opens_after_path, class_name: "Path", optional: true
  has_many :tracks, -> { order(:position) }, dependent: :destroy

  scope :published, -> { where(published: true) }
  scope :ordered, -> { order(:position) }

  validates :slug, presence: true, uniqueness: true
  validates :title, :description, presence: true
  validates :opens_after_missions, presence: true, numericality: { only_integer: true, greater_than: 0 }, if: :opens_after_missions?
  validates :opens_after_missions, absence: true, unless: :opens_after_missions?
  validates :opens_after_path, presence: true, if: :opens_after_first_track?
  validates :opens_after_path, absence: true, unless: :opens_after_first_track?
  validate :opens_after_another_path

  def to_param
    slug
  end

  # The published tracks that have a published mission to play, from loaded associations where present.
  def playable_tracks
    tracks.select { |track| track.published? && track.missions.any?(&:published?) }
  end

  def coming_soon?
    playable_tracks.none?
  end

  private
    def opens_after_another_path
      errors.add(:opens_after_path, "must be another path") if opens_after_path && opens_after_path == self
    end
end
