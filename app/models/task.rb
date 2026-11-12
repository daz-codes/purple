# An item on Blue's to-do list. Completed only by clicking the right link in a legitimate message.
class Task < ApplicationRecord
  belongs_to :shift
  has_many :links, dependent: :restrict_with_exception

  validates :key, presence: true, uniqueness: { scope: :shift_id }
  validates :title, presence: true
  validates :due_at_minute, :points, numericality: { only_integer: true, greater_than: 0 }
end
