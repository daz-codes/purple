require "test_helper"

class ShiftAttempt::HintableTest < ActiveSupport::TestCase
  setup do
    @attempt = ShiftAttempt.start(user: users(:one), shift: shifts(:month_end))
  end

  test "hints are revealed one at a time, cost no time, and run out" do
    assert_equal hints(:month_end_first), @attempt.next_hint
    assert_empty @attempt.revealed_hints

    @attempt.use_hint

    assert_equal [ hints(:month_end_first) ], @attempt.revealed_hints
    assert_nil @attempt.next_hint
    assert_equal [ 0, 1 ], [ @attempt.clock_minutes, @attempt.hints_used ]
    assert_raises(ShiftAttempt::Rejected, match: /no more hints/) { @attempt.use_hint }
  end
end
