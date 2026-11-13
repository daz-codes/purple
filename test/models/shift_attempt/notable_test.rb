require "test_helper"

# Month-end: the newsletter (there at the start) mentions the canteen's new menu, which this test
# treats as a detail worth saving.
class ShiftAttempt::NotableTest < ActiveSupport::TestCase
  setup do
    newsletter = messages(:newsletter)
    paragraph = newsletter.paragraphs["p1"]
    start = paragraph.text.index("new menu")
    newsletter.update!(details: [ { "key" => "menu", "label" => "The new menu", "sensitivity" => "internal", "anchor" => "p1",
                                    "quote" => "new menu", "quote_start" => start, "quote_end" => start + 8 } ])
    @attempt = ShiftAttempt.start(user: users(:one), shift: shifts(:month_end))
    @start = start
  end

  test "highlighted words become a note, with a neutral id and the words as they read" do
    @attempt.save_note(messages(:newsletter), "p1", from: @start, to: @start + 8)

    note = @attempt.notes.sole
    assert_equal "new menu", note.text
    assert_match(/\An\d+\z/, note.id)
    assert_equal [ note ], @attempt.notes_on(messages(:newsletter))
    assert_equal "save_note", @attempt.actions.last.kind
  end

  test "a clicked sentence is saved whole" do
    @attempt.save_note(messages(:newsletter), "p1s1")

    assert_equal "The canteen has a new menu.", @attempt.notes.sole.text
  end

  test "saving the same words again takes the note off" do
    2.times { @attempt.save_note(messages(:newsletter), "p1", from: @start, to: @start + 8) }

    assert_empty @attempt.notes
  end

  test "whether a note matches a detail is worked out privately, by the red-flag rules" do
    @attempt.save_note(messages(:newsletter), "p1", from: @start, to: @start + 8)
    @attempt.save_note(messages(:newsletter), "p1", from: 0, to: 3)

    matched, other = @attempt.notes
    assert_equal "menu", matched.detail_in(messages(:newsletter)).key
    assert_nil other.detail_in(messages(:newsletter))
  end

  test "only words can be saved, from a message in the inbox" do
    assert_raises(ShiftAttempt::Rejected, match: /Save words/) { @attempt.save_note(messages(:newsletter), "from") }
    assert_raises(ShiftAttempt::Rejected, match: /Save words/) { @attempt.save_note(messages(:newsletter), "p9") }

    @attempt.archive(messages(:newsletter))
    assert_raises(ShiftAttempt::Rejected, match: /already dealt with/) { @attempt.save_note(messages(:newsletter), "p1s1") }
  end
end
