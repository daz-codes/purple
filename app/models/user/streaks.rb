# Daily streaks: consecutive calendar days (Europe/London) with at least one finished shift or
# launched campaign. The first one each day also earns a small bonus on the side played.
module User::Streaks
  extend ActiveSupport::Concern

  TIME_ZONE = "Europe/London".freeze
  STREAK_BONUS = 10

  def self.day_of(time)
    time.in_time_zone(TIME_ZONE).to_date
  end

  # Counts a day played. Returns the bonus XP event if this was the day's first play, or nil.
  def record_play(side:, source:, at: Time.current)
    day = User::Streaks.day_of(at)
    return if last_played_on && last_played_on >= day

    streak = last_played_on == day - 1 ? current_streak + 1 : 1
    update!(current_streak: streak, longest_streak: [ longest_streak, streak ].max, last_played_on: day)
    award_xp(side:, amount: STREAK_BONUS, reason: :streak_bonus, source:, at:)
  end

  # The streak as it stands today: it's only still alive if the player played today or yesterday.
  def streak_today(today: User::Streaks.day_of(Time.current))
    last_played_on && last_played_on >= today - 1 ? current_streak : 0
  end
end
