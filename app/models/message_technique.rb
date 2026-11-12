class MessageTechnique < ApplicationRecord
  belongs_to :message
  belongs_to :technique

  validates :technique_id, uniqueness: { scope: :message_id }
end
