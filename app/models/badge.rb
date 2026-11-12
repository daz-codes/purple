class Badge < ApplicationRecord
  enum :side, { blue: "blue", red: "red", purple: "purple", any: "any" }, prefix: true, validate: true

  has_many :user_badges, dependent: :restrict_with_exception

  scope :ordered, -> { order(:position) }

  validates :key, presence: true, uniqueness: true
  validates :name, :description, presence: true
end
