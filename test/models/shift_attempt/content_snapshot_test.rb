require "test_helper"
require_relative "../../../db/migrate/20261116150100_snapshot_existing_blue_results"

class ShiftAttempt::ContentSnapshotTest < ActiveSupport::TestCase
  test "completed results retain content, scores and stars after content edits and deletions" do
    attempt = ShiftAttempt.start(user: users(:one), shift: shifts(:month_end))
    attempt.archive(messages(:newsletter))
    attempt.flag(messages(:fake_invoice), "from")
    attempt.visit(links(:fake_invoice_link))
    attempt.close_tab
    attempt.report(messages(:fake_invoice))
    attempt.use_hint
    attempt.clock_off
    before = result(attempt)

    messages(:newsletter).update!(points: 100, body_html: "<p>New text.</p>")
    messages(:fake_invoice).destroy!
    shifts(:month_end).hints.destroy_all
    shifts(:month_end).update!(par_minutes: 90, title: "A different shift", learning_summary: "Changed.")
    tracks(:basics).update!(title: "A different track")

    assert_equal before, result(attempt.reload)
    assert_equal attempt.score, attempt.scorecard.total
    assert attempt.scorecard.shift.readonly?
    assert attempt.scorecard.messages.all? { |entry| entry.message.readonly? }
  end

  test "a copy taken under an older schema still loads: removed columns are dropped and new ones take their defaults" do
    captured = ShiftAttempt::ContentSnapshot.capture(shifts(:month_end))
    captured["retired_column"] = "gone"
    captured.delete("persona")
    captured["messages"].each { |message| message.delete("needs") }

    shift = ShiftAttempt::ContentSnapshot.new(captured).shift
    assert_equal({}, shift.persona)
    assert shift.messages.all? { |message| message.needs == [] }
    assert_not shift.has_attribute?(:retired_column)
  end

  test "a finished attempt builds its scorecard once" do
    attempt = ShiftAttempt.start(user: users(:one), shift: shifts(:month_end))
    attempt.clock_off

    assert_same attempt.scorecard, attempt.scorecard
    assert_not_same attempt.scorecard, attempt.reload.scorecard
  end

  test "the captured graph resolves story links and private details without querying live messages" do
    shift = shifts(:site_visit)
    snapshot = ShiftAttempt::ContentSnapshot.new(ShiftAttempt::ContentSnapshot.capture(shift)).shift
    shift.messages.destroy_all

    question = snapshot.messages.find { |message| message.key == "sam_text" }
    assert_equal "laptop_text", question.answer_source.key
    assert_equal snapshot, question.shift
    red_flag = snapshot.messages.find { |message| message.key == "it_chat" }.red_flags.find(&:contradicts_key)
    assert_equal "laptop_text", red_flag.contradicted_message.key
    assert_equal shift.persona, snapshot.persona
  end

  test "the upgrade backfill captures existing finished content without rewriting scores or XP" do
    attempt = ShiftAttempt.start(user: users(:one), shift: shifts(:month_end))
    attempt.clock_off
    recorded_score = attempt.score
    xp = users(:one).reload.xp_total
    expected = result(attempt)
    attempt.update_column(:result_content, {})

    migration = SnapshotExistingBlueResults.new
    migration.suppress_messages { migration.up }
    assert_not_empty attempt.reload.result_content
    assert_equal expected, result(attempt)
    assert_equal recorded_score, attempt.score
    assert_equal xp, users(:one).reload.xp_total
    assert_not ShiftAttempt.start(user: users(:two), shift: shifts(:month_end)).result_content.present?
  end

  private
    def result(attempt)
      card = attempt.scorecard
      [ card.total, card.stars, card.hint_penalty, card.best_possible, card.shift.title, card.shift.track.title,
        card.shift.learning_summary, card.messages.map { |entry| [ entry.message.body_html, entry.points, entry.outcome ] } ]
    end
end
