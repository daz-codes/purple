require "test_helper"

class MissionAttempt::InterceptScorecardTest < ActiveSupport::TestCase
  setup do
    @attempt = MissionAttempt.start(user: users(:one), mission: missions(:kettle))
  end

  test "every flag first time, no hints: perfect, three stars, the full score" do
    @attempt.submit_flag(intercepts(:opening), "biscuit tin")
    @attempt.submit_flag(intercepts(:wrapped), "old lighthouse")
    card = @attempt.reload.scorecard

    assert_kind_of MissionAttempt::InterceptScorecard, card
    assert card.perfect?
    assert_equal [ 200, 200, 3, 2 ], [ card.total, card.best_possible, card.stars, card.flags_found ]
    assert_equal 200, @attempt.score
  end

  test "each wrong answer before the flag costs 10, never below half the intercept's points" do
    2.times { |guess| @attempt.submit_flag(intercepts(:opening), "nope #{guess}") }
    @attempt.submit_flag(intercepts(:opening), "biscuit tin")
    4.times { |guess| @attempt.submit_flag(intercepts(:wrapped), "nope #{guess}") }
    @attempt.submit_flag(intercepts(:wrapped), "old lighthouse")
    card = @attempt.reload.scorecard

    opening, wrapped = card.intercepts
    assert_equal [ 2, 80 ], [ opening.wrong_answers, opening.points ]
    assert_equal [ 4, 60 ], [ wrapped.wrong_answers, wrapped.points ]
    assert_not card.perfect?
    assert_equal 2, card.stars # 140 of 200
  end

  test "the floor at half: a flag found on the last try" do
    intercept = intercepts(:opening)
    intercept.update!(points: 50)
    4.times { |guess| @attempt.submit_flag(intercept, "nope #{guess}") }
    @attempt.submit_flag(intercept, "biscuit tin")

    assert_equal 25, @attempt.reload.scorecard.intercepts.first.points
  end

  test "an unsolved intercept scores nothing, and standing down ends the mission" do
    @attempt.submit_flag(intercepts(:opening), "biscuit tin")
    @attempt.stand_down
    card = @attempt.scorecard

    assert @attempt.stood_down?
    assert_equal [ 100, 1, 1 ], [ card.total, card.flags_found, card.stars ] # 50%
  end

  test "hints cost their share of the best possible score" do
    @attempt.use_hint
    @attempt.submit_flag(intercepts(:opening), "biscuit tin")
    @attempt.submit_flag(intercepts(:wrapped), "old lighthouse")
    card = @attempt.reload.scorecard

    assert_equal 20, card.hint_penalty
    assert_equal 180, card.total
    assert_not card.perfect?
    assert_equal 3, card.stars # 90%
  end

  test "guessing never pays: five wrong answers everywhere scores nothing" do
    [ intercepts(:opening), intercepts(:wrapped) ].each do |intercept|
      MissionAttempt::Decoding::MAX_WRONG.times { |guess| @attempt.submit_flag(intercept, "guess #{guess}") }
    end

    assert @attempt.completed?
    assert_equal [ 0, 0 ], [ @attempt.score, @attempt.scorecard.stars ]
  end

  test "a finished attempt is judged on the intercepts as they were" do
    @attempt.submit_flag(intercepts(:opening), "biscuit tin")
    @attempt.stand_down
    intercepts(:opening).update!(points: 500, solution: "Changed.")
    intercepts(:wrapped).destroy!

    card = @attempt.reload.scorecard
    assert_equal [ 100, 200 ], [ card.total, card.best_possible ]
    assert_equal "TEAPOT CALLS THE BASE THE BISCUIT TIN.", card.intercepts.first.intercept.solution
    assert card.intercepts.first.intercept.readonly?
  end
end
