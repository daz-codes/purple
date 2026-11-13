# Something a player finishes that counts towards their progress: a shift attempt or a Workshop
# campaign. When it finishes, the player's XP (if it's their scored attempt), streak and badges are
# brought up to date. Only confirmed players earn anything.
#
# Including models define #side (blue or red), #xp_reason, #just_finished? and #finished_at.
module Rewarded
  extend ActiveSupport::Concern

  included do
    after_update_commit :reward, if: :just_finished?
  end

  private
    def reward
      return unless user.earns_xp?

      user.transaction do
        # Lock first: two attempts finishing at once must not both count as the day's first play.
        user.lock!
        user.award_xp(side:, amount: score, reason: xp_reason, source: self, at: finished_at) if scored?
        user.record_play(side:, source: self, at: finished_at)
      end
      AwardBadgesJob.perform_later(user, self)
    end
end
