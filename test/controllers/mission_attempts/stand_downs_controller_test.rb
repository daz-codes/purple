require "test_helper"

class MissionAttempts::StandDownsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @attempt = MissionAttempt.start(user: users(:one), mission: missions(:month_end))
    sign_in_as users(:one)
  end

  test "standing down ends the mission and goes to the debrief" do
    post mission_attempt_stand_down_path(@attempt), as: :turbo_stream

    assert_redirected_to mission_attempt_path(@attempt)
    assert @attempt.reload.stood_down?

    follow_redirect!
    assert_select "[data-testid=debrief-ending]", text: /You stood down/
  end

  test "standing down a finished mission just goes to its debrief" do
    @attempt.stand_down
    post mission_attempt_stand_down_path(@attempt), as: :turbo_stream

    assert_redirected_to mission_attempt_path(@attempt)
  end
end
