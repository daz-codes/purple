require "test_helper"

class MissionAttempts::Intercepts::FlagsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @attempt = MissionAttempt.start(user: users(:one), mission: missions(:kettle))
    @ref = @attempt.intercept_ref(intercepts(:opening))
    sign_in_as users(:one)
  end

  test "a right flag says so, and re-renders the intercept as found" do
    post mission_attempt_intercept_flags_path(@attempt, @ref), params: { answer: "Biscuit tin" }, as: :turbo_stream

    assert_response :success
    assert_select "turbo-stream[target=mission_notice] template", text: /Flag found/
    assert_select "turbo-stream[target=mission_intercept] template", text: /Flag found: Biscuit tin/
    assert_select "turbo-stream[target=mission_intercepts] template", text: /Found ✓/
    assert @attempt.reload.solved?(intercepts(:opening))
  end

  test "a wrong flag says how many tries are left, and nothing else" do
    post mission_attempt_intercept_flags_path(@attempt, @ref), params: { answer: "teapot" }, as: :turbo_stream

    assert_select "turbo-stream[target=mission_notice] template", text: "Not that. 4 tries left on this intercept."
    assert_no_match(/biscuit/i, response.body)
  end

  test "the last intercept solved finishes the mission and goes to the debrief" do
    @attempt.submit_flag(intercepts(:wrapped), "old lighthouse")
    post mission_attempt_intercept_flags_path(@attempt, @ref), params: { answer: "biscuit tin" }, as: :turbo_stream

    assert_redirected_to mission_attempt_path(@attempt)
    assert @attempt.reload.completed?
  end

  test "a refused submission changes nothing" do
    @attempt.submit_flag(intercepts(:opening), "biscuit tin")
    post mission_attempt_intercept_flags_path(@attempt, @ref), params: { answer: "biscuit tin" }, as: :turbo_stream

    assert_response :unprocessable_content
    assert_equal 1, @attempt.reload.submissions(intercepts(:opening)).size
  end

  test "an intercept is only found by this attempt's ref" do
    post mission_attempt_intercept_flags_path(@attempt, "new_codename"), params: { answer: "biscuit tin" }, as: :turbo_stream
    assert_response :not_found

    other = MissionAttempt.start(user: users(:two), mission: missions(:kettle))
    post mission_attempt_intercept_flags_path(other, other.intercept_ref(intercepts(:opening))), params: { answer: "biscuit tin" }
    assert_response :not_found
  end

  test "answers are filtered from the logs" do
    assert_equal "[FILTERED]", ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters).filter("answer" => "Biscuit tin")["answer"]
  end

  test "guessing fast is rate limited" do
    # The test cache stores nothing, so make this the 11th guess in a minute.
    store = MissionAttempts::Intercepts::FlagsController.cache_store
    store.define_singleton_method(:increment) { |*| 11 }
    post mission_attempt_intercept_flags_path(@attempt, @ref), params: { answer: "biscuit tin" }, as: :turbo_stream

    assert_response :unprocessable_content
    assert_match(/a lot of guesses/, response.body)
    assert_not @attempt.reload.solved?(intercepts(:opening))
  ensure
    store.singleton_class.remove_method(:increment)
  end
end
