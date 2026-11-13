require "test_helper"

class ShiftAttempts::Messages::NotesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @attempt = ShiftAttempt.start(user: users(:one), shift: shifts(:month_end))
    @attempt.read(messages(:newsletter))
    @ref = @attempt.message_ref(messages(:newsletter))
    sign_in_as users(:one)
  end

  test "saving words keeps the reader in notes mode and lists the note with the player's details" do
    post shift_attempt_message_notes_path(@attempt, @ref), params: { anchor: "p1s1" }, as: :turbo_stream

    assert_response :success
    assert_equal [ "The canteen has a new menu." ], @attempt.reload.notes.map(&:text)
    assert_select "turbo-stream[target=shift_reader] template [data-flag-mode-mode-value=note]"
    assert_select "turbo-stream[target=shift_reader] template [data-testid=your-notes]", text: /new menu/
    assert_select "turbo-stream[target=shift_persona] template [data-testid=notes-list]", text: /new menu/
  end

  test "a header isn't words, so it can't be saved" do
    post shift_attempt_message_notes_path(@attempt, @ref), params: { anchor: "from" }, as: :turbo_stream

    assert_response :unprocessable_content
  end
end
