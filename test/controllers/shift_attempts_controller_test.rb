require "test_helper"

class ShiftAttemptsControllerTest < ActionDispatch::IntegrationTest
  test "starting a shift needs a signed-in player" do
    post shift_attempts_path(shifts(:month_end))

    assert_redirected_to new_session_path
    assert_equal 0, ShiftAttempt.count
  end

  test "starting a shift twice resumes the same attempt" do
    sign_in_as users(:one)

    post shift_attempts_path(shifts(:month_end))
    attempt = ShiftAttempt.sole
    assert_redirected_to shift_attempt_path(attempt)

    post shift_attempts_path(shifts(:month_end))
    assert_redirected_to shift_attempt_path(attempt)
    assert_equal 1, ShiftAttempt.count
  end

  test "an attempt can only be seen by its owner" do
    attempt = ShiftAttempt.start(user: users(:one), shift: shifts(:month_end))
    sign_in_as users(:two)

    get shift_attempt_path(attempt)
    assert_response :not_found
  end

  test "the play screen contains no answers" do
    attempt = ShiftAttempt.start(user: users(:one), shift: shifts(:month_end))
    Shift::Engine.new(attempt).perform("wait")
    Shift::Engine.new(attempt).perform("open_message", message_ref: attempt.message_ref(messages(:fake_invoice)))
    sign_in_as users(:one)

    get shift_attempt_path(attempt)

    assert_response :success
    assert_select "[data-actual-url]", 1
    assert_no_answers_in response.body
  end

  private
    def assert_no_answers_in(html)
      secrets = %w[ legit outcome completes_task bait_landing credential_harvest real_invoice fake_invoice pay_supplier
                    lookalike_domain T1583 ] + [ red_flags(:lookalike).label, "freemail.test", "haven't changed" ]
      secrets.each do |secret|
        assert_not_includes html, secret
        assert_not_includes html, ERB::Util.html_escape(secret)
      end
    end
end
