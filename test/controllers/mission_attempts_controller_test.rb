require "test_helper"

class MissionAttemptsControllerTest < ActionDispatch::IntegrationTest
  test "starting a mission needs a signed-in player" do
    post mission_attempts_path(missions(:month_end))

    assert_redirected_to new_session_path
    assert_equal 0, MissionAttempt.count
  end

  test "a mission on an unpublished path can't be started" do
    paths(:phishing).update!(published: false)
    sign_in_as users(:one)

    post mission_attempts_path(missions(:month_end))

    assert_response :not_found
    assert_equal 0, MissionAttempt.count
  end

  test "starting a mission twice resumes the same attempt" do
    sign_in_as users(:one)

    post mission_attempts_path(missions(:month_end))
    attempt = MissionAttempt.sole
    assert_redirected_to mission_attempt_path(attempt)

    post mission_attempts_path(missions(:month_end))
    assert_redirected_to mission_attempt_path(attempt)
    assert_equal 1, MissionAttempt.count
  end

  test "an attempt can only be seen by its owner" do
    attempt = MissionAttempt.start(user: users(:one), mission: missions(:month_end))
    sign_in_as users(:two)

    get mission_attempt_path(attempt)
    assert_response :not_found
  end

  test "the play screen contains no answers" do
    attempt = MissionAttempt.start(user: users(:one), mission: missions(:month_end))
    attempt.archive(messages(:newsletter))
    attempt.read(messages(:fake_invoice))
    sign_in_as users(:one)

    get mission_attempt_path(attempt)

    assert_response :success
    assert_select "[data-actual-url]", 1
    assert_no_answers_in response.body
  end

  test "a finished debrief shows the content and score it was judged against" do
    attempt = MissionAttempt.start(user: users(:one), mission: missions(:month_end))
    attempt.archive(messages(:newsletter))
    attempt.report(messages(:fake_invoice))
    attempt.stand_down
    original_title = missions(:month_end).title
    original_summary = missions(:month_end).learning_summary
    messages(:newsletter).update!(points: 100)
    messages(:fake_invoice).destroy!
    missions(:month_end).update!(title: "Changed title", learning_summary: "Changed summary")
    sign_in_as users(:one)

    get mission_attempt_path(attempt)
    assert_response :success
    assert_select "h1", text: original_title
    assert_select "[data-testid=score]", text: attempt.score.to_s
    assert_includes response.body, ERB::Util.html_escape(original_summary)
    assert_select "[data-testid=debrief-message]", text: /URGENT invoice/
    assert_not_includes response.body, "Changed title"
  end

  private
    def assert_no_answers_in(html)
      secrets = %w[ legit outcome expects bait_landing credential_harvest real_invoice fake_invoice newsletter supplier_thanks
                    arrives_after lookalike_domain T1583 ] +
        [ red_flags(:lookalike).label, red_flags(:pay_today).label, "Thanks for approving", "freemail.test", "haven't changed" ]
      secrets.each do |secret|
        assert_not_includes html, secret
        assert_not_includes html, ERB::Util.html_escape(secret)
      end
    end
end
