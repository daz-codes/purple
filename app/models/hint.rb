class Hint < ApplicationRecord
  belongs_to :shift

  validates :body, presence: true
  validates :position, numericality: { only_integer: true }, uniqueness: { scope: :shift_id }
  validates :penalty_percent, numericality: { only_integer: true, in: 0..100 }
end
