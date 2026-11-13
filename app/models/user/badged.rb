# Badges a player has earned. Awarded at most once each; each also earns a little XP on the side of
# whatever earned it.
module User::Badged
  extend ActiveSupport::Concern

  BADGE_XP = 25

  # Awards every badge the source has just earned. Returns the badges that are new.
  def award_badges_for(source)
    return [] unless earns_xp?

    keys = Badge::Rulebook.new(self, source).earned_keys - badges.pluck(:key)
    Badge.where(key: keys).ordered.filter_map do |badge|
      user_badges.create!(badge:, awarded_at: Time.current)
      award_xp(side: source.side, amount: BADGE_XP, reason: :badge_awarded, source: badge)
      badge
    rescue ActiveRecord::RecordNotUnique
      nil
    end
  end
end
