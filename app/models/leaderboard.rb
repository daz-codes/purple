# A ranking of players by XP: for one side or both (overall), this ISO week or all time, and for timed
# or relaxed play. Built from the XP ledger, so a week's board is just that week's events.
#
# Only XP for playing counts (a player's first scored attempt at each shift or target): streak bonuses
# and badges raise a player's level but not their rank, so daily replays can't climb the board.
#
# Ties go to whoever reached the score first: the player whose last counted event is earliest. Players
# who've opted out of leaderboards aren't ranked. Rankings are cached for a minute.
class Leaderboard
  SIDES = %w[ blue red overall ].freeze
  PERIODS = %w[ week all ].freeze
  TIME_ZONE = User::Streaks::TIME_ZONE
  REASONS = %w[ shift_completed workshop_completed ].freeze
  SIZE = 50
  CACHE_FOR = 60.seconds

  Entry = Data.define(:rank, :user_id, :display_name, :preferred_side, :xp)

  attr_reader :side, :period, :relaxed

  def initialize(side: "overall", period: "week", relaxed: false, now: Time.current)
    @side = side.to_s.in?(SIDES) ? side.to_s : "overall"
    @period = period.to_s.in?(PERIODS) ? period.to_s : "week"
    @relaxed = ActiveModel::Type::Boolean.new.cast(relaxed) || false
    @now = now
  end

  # The top of the board.
  def entries
    Rails.cache.fetch(cache_key, expires_in: CACHE_FOR) { ranked.limit(SIZE).map { |row| entry(row) } }
  end

  # A player's own place, whether or not they're near the top. Nil if they haven't scored.
  def entry_for(user)
    return unless user

    row = User.from(ranked_relation.reorder(nil), :ranked).select("ranked.*").where("ranked.user_id = ?", user.id).take
    entry(row) if row
  end

  def week_starts_at
    @now.in_time_zone(TIME_ZONE).beginning_of_week(:monday)
  end

  private
    def ranked
      ranked_relation
    end

    # Each player's XP in this board, with their rank, best first.
    def ranked_relation
      @ranked_relation ||= begin
        totals = XpEvent.joins(:user).where(users: { leaderboard_opt_out: false }).where(relaxed:, reason: REASONS)
        totals = totals.where(side:) unless side == "overall"
        totals = totals.where(occurred_at: week_starts_at..) if period == "week"
        totals = totals.group(:user_id).select("xp_events.user_id, SUM(xp_events.amount) AS earned, MAX(xp_events.occurred_at) AS reached_at")

        User.from(totals, :totals).joins("JOIN users ON users.id = totals.user_id")
          .select("totals.user_id, totals.earned, users.display_name, users.preferred_side, " \
                  "RANK() OVER (ORDER BY totals.earned DESC, totals.reached_at ASC) AS rank")
          .order("rank, users.display_name")
      end
    end

    def entry(row)
      Entry.new(rank: row.rank, user_id: row.user_id, display_name: row.display_name, preferred_side: row.preferred_side, xp: row.earned)
    end

    def cache_key
      [ "leaderboard", side, period, relaxed, (week_starts_at.to_date if period == "week") ]
    end
end
