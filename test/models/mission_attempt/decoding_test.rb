require "test_helper"

class MissionAttempt::DecodingTest < ActiveSupport::TestCase
  setup do
    @attempt = MissionAttempt.start(user: users(:one), mission: missions(:kettle))
    @opening = intercepts(:opening)
    @wrapped = intercepts(:wrapped)
  end

  test "a right flag is logged with what was typed, and solves the intercept" do
    assert @attempt.submit_flag(@opening, "  Biscuit tin. ")

    action = @attempt.actions.last
    assert_equal [ "submit_flag", "new_codename", { "answer" => "Biscuit tin.", "correct" => true } ],
      [ action.kind, action.target_key, action.result ]
    assert @attempt.solved?(@opening)
    assert @attempt.closed?(@opening)
    assert @attempt.open?, "one intercept is still open"
  end

  test "a wrong flag costs a try, and the intercept closes after the last one" do
    (MissionAttempt::Decoding::MAX_WRONG - 1).times { |guess| assert_not @attempt.submit_flag(@opening, "guess #{guess}") }
    assert_equal 1, @attempt.tries_left(@opening)
    assert_not @attempt.closed?(@opening)

    assert_not @attempt.submit_flag(@opening, "last guess")
    assert @attempt.closed?(@opening)
    assert_not @attempt.solved?(@opening)
    error = assert_raises(MissionAttempt::Rejected) { @attempt.submit_flag(@opening, "Biscuit tin") }
    assert_match(/closed/, error.message)
  end

  test "a solved intercept takes no more answers" do
    @attempt.submit_flag(@opening, "biscuit tin")
    assert_raises(MissionAttempt::Rejected, match: /already found/) { @attempt.submit_flag(@opening, "biscuit tin") }
    assert_equal 1, @attempt.submissions(@opening).size
  end

  test "an empty answer isn't a try" do
    assert_raises(MissionAttempt::Rejected) { @attempt.submit_flag(@opening, " \u0000\t ") }
    assert_equal MissionAttempt::Decoding::MAX_WRONG, @attempt.tries_left(@opening)
  end

  test "answers are capped, with control characters taken out" do
    @attempt.submit_flag(@opening, "a\u0000b\u0007c" + "x" * 500)
    answer = @attempt.actions.last.result["answer"]
    assert_equal MissionAttempt::Decoding::ANSWER_LIMIT, answer.size
    assert answer.start_with?("a b c")
  end

  test "the mission is cleared once every intercept is solved or closed" do
    @attempt.submit_flag(@opening, "biscuit tin")
    MissionAttempt::Decoding::MAX_WRONG.times { |guess| @attempt.submit_flag(@wrapped, "pier #{guess}") }

    assert @attempt.completed?
    assert @attempt.scored?
  end

  test "a signals mission doesn't end just because it has no messages" do
    @attempt.use_hint
    assert @attempt.open?
  end

  test "intercepts are known by an opaque ref, different in every attempt" do
    ref = @attempt.intercept_ref(@opening)
    other = MissionAttempt.start(user: users(:two), mission: missions(:kettle))

    assert_match(/\A\h{16}\z/, ref)
    assert_not_includes ref, @opening.key
    assert_not_equal ref, other.intercept_ref(@opening)
    assert_not_equal ref, @attempt.message_ref(@opening)
    assert_equal @opening, @attempt.find_intercept(ref)
    assert_nil @attempt.find_intercept(other.intercept_ref(@opening))
    assert_nil @attempt.find_intercept(@opening.key)
  end

  test "nothing can be submitted once the mission is over" do
    @attempt.stand_down
    assert_raises(MissionAttempt::Rejected) { @attempt.submit_flag(@opening, "biscuit tin") }
  end
end
