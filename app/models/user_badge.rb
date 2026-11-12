class UserBadge < ApplicationRecord
  belongs_to :user
  belongs_to :badge

  validates :badge_id, uniqueness: { scope: :user_id }
  validates :awarded_at, presence: true
end
