# One Red's Workshop attempt at a target. Red builds it card by card (a draft), then launches it:
# the email is assembled from the cards, the bots judge it, and the result is stored so it can be
# replayed exactly. Red acts on it through choose, unchoose and launch.
class RedCampaign < ApplicationRecord
  class Rejected < StandardError; end

  include Buildable, Launchable

  enum :status, { draft: "draft", launched: "launched" }, validate: true

  belongs_to :user
  belongs_to :target

  has_secure_token :token, length: 32

  before_validation -> { self.seed ||= SecureRandom.random_number(2**31) }, on: :create

  def self.start(user:, target:)
    user.red_campaigns.draft.find_or_create_by!(target:)
  rescue ActiveRecord::RecordNotUnique
    user.red_campaigns.draft.find_by!(target:)
  end

  def to_param
    token
  end
end
