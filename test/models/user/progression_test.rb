require "test_helper"

class User::ProgressionTest < ActiveSupport::TestCase
  setup { @user = users(:one) }

  test "levels: level 1 from nothing, then 100 * (n - 1)^1.5 XP for level n" do
    assert_equal [ 0, 100, 283, 520 ], (1..4).map { |level| User.xp_for_level(level) }
    assert_equal [ 1, 1, 2, 2, 3, 4 ], [ 0, 99, 100, 282, 283, 520 ].map { |xp| User.level_for(xp) }
  end

  test "XP goes into the ledger and the side's total and level together, and xp_total is both sides" do
    event = @user.award_xp(side: "blue", amount: 120, reason: :shift_completed)
    @user.award_xp(side: "red", amount: 40, reason: :workshop_completed)

    assert_equal [ "blue", 120, "shift_completed" ], [ event.side, event.amount, event.reason ]
    assert_equal [ 120, 2, 40, 1, 160 ], @user.reload.values_at(:blue_xp, :blue_level, :red_xp, :red_level, :xp_total)
    assert_equal 2, @user.xp_events.count
  end

  test "each source earns each kind of XP once" do
    attempt = ShiftAttempt.start(user: @user, shift: shifts(:month_end))

    assert @user.award_xp(side: "blue", amount: 50, reason: :shift_completed, source: attempt)
    assert_nil @user.award_xp(side: "blue", amount: 50, reason: :shift_completed, source: attempt)
    assert_equal 50, @user.reload.blue_xp
  end

  test "the database keeps xp_total the sum of the sides" do
    assert_raises(ActiveRecord::StatementInvalid) { @user.update_column(:xp_total, 5) }
  end

  test "progress through the current level, and what's left to the next" do
    @user.award_xp(side: "blue", amount: 150, reason: :shift_completed)

    assert_in_delta (150 - 100).fdiv(283 - 100), @user.level_progress("blue")
    assert_equal 133, @user.xp_to_next_level("blue")
  end

  test "a preferred side is blue or red" do
    @user.choose_side("red")
    assert_equal "red", @user.reload.preferred_side
    assert_raises(ActiveRecord::RecordInvalid) { @user.choose_side("green") }
  end
end
