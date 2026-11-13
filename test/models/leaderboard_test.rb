require "test_helper"

class LeaderboardTest < ActiveSupport::TestCase
  setup do
    travel_to Time.zone.parse("2026-11-12 12:00") # a Thursday
    @blue, @red = users(:one), users(:two)
  end

  test "ranks players by XP for a side, best first" do
    xp(@blue, "blue", 120)
    xp(@red, "blue", 50)
    xp(@red, "red", 300)

    assert_equal [ [ 1, "blue_one", 120 ], [ 2, "red_two", 50 ] ], board(side: "blue").map { |e| [ e.rank, e.display_name, e.xp ] }
    assert_equal [ [ 1, "red_two", 300 ] ], board(side: "red").map { |e| [ e.rank, e.display_name, e.xp ] }
    assert_equal [ [ 1, "red_two", 350 ], [ 2, "blue_one", 120 ] ], board(side: "overall").map { |e| [ e.rank, e.display_name, e.xp ] }
  end

  test "the week starts on Monday in London, and all time counts everything" do
    xp(@blue, "blue", 100, at: "2026-11-09 00:30") # this Monday
    xp(@red, "blue", 500, at: "2026-11-08 23:30")  # last Sunday

    assert_equal [ "blue_one" ], board(period: "week").map(&:display_name)
    assert_equal %w[ red_two blue_one ], board(period: "all").map(&:display_name)
  end

  test "a tie goes to whoever reached the score first" do
    xp(@red, "blue", 100, at: "2026-11-11 10:00")
    xp(@blue, "blue", 100, at: "2026-11-10 10:00")

    assert_equal [ [ 1, "blue_one" ], [ 2, "red_two" ] ], board.map { |e| [ e.rank, e.display_name ] }
  end

  test "relaxed play is ranked separately, and players who opt out aren't ranked" do
    xp(@blue, "blue", 100)
    xp(@red, "blue", 200, relaxed: true)

    assert_equal [ "blue_one" ], board(relaxed: false).map(&:display_name)
    assert_equal [ "red_two" ], board(relaxed: true).map(&:display_name)

    @blue.update!(leaderboard_opt_out: true)
    assert_empty board(relaxed: false)
  end

  test "a player's own place, wherever they are, or nil if they haven't scored" do
    xp(@red, "blue", 300)
    xp(@blue, "blue", 100)

    assert_equal [ 2, 100 ], Leaderboard.new(side: "blue").entry_for(@blue).then { |e| [ e.rank, e.xp ] }
    assert_nil Leaderboard.new(side: "blue").entry_for(users(:unconfirmed))
  end

  test "unknown tabs fall back to overall, this week" do
    board = Leaderboard.new(side: "green", period: "forever")

    assert_equal [ "overall", "week" ], [ board.side, board.period ]
  end

  test "only XP for playing ranks: streak bonuses and badges don't" do
    xp(@blue, "blue", 100)
    @red.xp_events.create!(side: "blue", amount: 10, reason: :streak_bonus, occurred_at: Time.zone.parse("2026-11-12 09:00"))
    @red.xp_events.create!(side: "blue", amount: 25, reason: :badge_awarded, occurred_at: Time.zone.parse("2026-11-12 09:00"))

    assert_equal [ [ "blue_one", 100 ] ], board(side: "blue").map { |entry| [ entry.display_name, entry.xp ] }
    assert_nil Leaderboard.new(side: "blue").entry_for(@red)
  end

  private
    def xp(user, side, amount, at: "2026-11-12 09:00", relaxed: false)
      user.xp_events.create!(side:, amount:, reason: :shift_completed, occurred_at: Time.zone.parse(at), relaxed:)
    end

    def board(side: "blue", period: "week", relaxed: false)
      Leaderboard.new(side:, period:, relaxed:).entries
    end
end
