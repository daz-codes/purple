# The Intercept of the day: one signals mission from the daily track, the same for everyone on a given
# day (Europe/London, like streaks), working through the pool in order. It's an ordinary mission, so it
# earns Blue XP the first time it's played and counts towards the day's streak.
class DailyIntercept
  attr_reader :day

  def initialize(day: User::Streaks.day_of(Time.current))
    @day = day
  end

  def mission
    return @mission if defined?(@mission)

    pool = Mission.playable.merge(Track.where(daily: true)).reorder("missions.position", "missions.id").to_a
    @mission = pool.any? ? pool[day.jd % pool.size] : nil
  end

  # Whether the player finished today's intercept today (completed or stood down).
  def done_by?(user)
    return false unless mission && user

    zone = ActiveSupport::TimeZone[User::Streaks::TIME_ZONE]
    user.mission_attempts.where(mission:, status: User::Unlocks::ENDED_BY_PLAYER)
      .where(completed_at: zone.local(day.year, day.month, day.day).all_day).exists?
  end
end
