require "test_helper"

class ShiftAttemptActionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @attempt = ShiftAttempt.start(user: users(:one), shift: shifts(:month_end))
    sign_in_as users(:one)
  end

  test "an action updates the clock, meters and panes with Turbo Streams" do
    post shift_attempt_actions_path(@attempt), params: { kind: "expand_headers", message: "m1" }, as: :turbo_stream

    assert_response :success
    assert_equal 1, @attempt.reload.clock_minutes
    %w[ shift_status shift_tasks shift_inbox shift_reader ].each do |target|
      assert_select "turbo-stream[action=replace][target=#{target}]"
    end
  end

  test "new mail is announced when the clock reaches it" do
    post shift_attempt_actions_path(@attempt), params: { kind: "wait" }, as: :turbo_stream

    assert_select "turbo-stream[target=shift_notice] template", text: "1 new message arrived."
  end

  test "a rejected action changes nothing and says why" do
    post shift_attempt_actions_path(@attempt), params: { kind: "open_message", message: "m2" }, as: :turbo_stream

    assert_response :unprocessable_content
    assert_select "turbo-stream[target=shift_notice] template", text: "That message isn't in your inbox."
    assert_empty @attempt.attempt_actions
  end

  test "without Turbo the player is sent back to the play screen" do
    post shift_attempt_actions_path(@attempt), params: { kind: "open_message", message: "m1" }

    assert_redirected_to shift_attempt_path(@attempt)
  end

  test "an action that ends the shift goes to the results" do
    @attempt.update!(clock_minutes: 29)
    post shift_attempt_actions_path(@attempt), params: { kind: "expand_headers", message: "m1" }, as: :turbo_stream

    assert_redirected_to shift_attempt_path(@attempt)
    assert @attempt.reload.timed_out?
  end

  test "players can't act on someone else's attempt" do
    sign_in_as users(:two)
    post shift_attempt_actions_path(@attempt), params: { kind: "open_message", message: "m1" }

    assert_response :not_found
    assert_empty @attempt.attempt_actions
  end

  test "ending the shift shows the results" do
    post shift_attempt_completion_path(@attempt)

    assert_redirected_to shift_attempt_path(@attempt)
    assert @attempt.reload.completed?

    follow_redirect!
    assert_select "[data-testid=score]", "0"
    assert_select "h1", "Month-end"
  end
end
