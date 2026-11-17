require "test_helper"

class MissionAttempt::HintableTest < ActiveSupport::TestCase
  setup do
    @attempt = MissionAttempt.start(user: users(:one), mission: missions(:month_end))
  end

  test "hints are revealed one at a time, cost no time, and run out" do
    assert_equal hints(:month_end_first), @attempt.next_hint
    assert_empty @attempt.revealed_hints

    @attempt.use_hint

    assert_equal [ hints(:month_end_first) ], @attempt.revealed_hints
    assert_nil @attempt.next_hint
    assert_equal [ 0, 1 ], [ @attempt.penalty_seconds, @attempt.hints_used ]
    assert_raises(MissionAttempt::Rejected, match: /no more hints/) { @attempt.use_hint }
  end
end
