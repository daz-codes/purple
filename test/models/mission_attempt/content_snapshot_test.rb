require "test_helper"
require_relative "../../../db/migrate/20261116150100_snapshot_existing_blue_results"

class MissionAttempt::ContentSnapshotTest < ActiveSupport::TestCase
  test "completed results retain content, scores and stars after content edits and deletions" do
    attempt = MissionAttempt.start(user: users(:one), mission: missions(:month_end))
    attempt.archive(messages(:newsletter))
    attempt.flag(messages(:fake_invoice), "from")
    attempt.visit(links(:fake_invoice_link))
    attempt.close_tab
    attempt.report(messages(:fake_invoice))
    attempt.use_hint
    attempt.stand_down
    before = result(attempt)

    messages(:newsletter).update!(points: 100, body_html: "<p>New text.</p>")
    messages(:fake_invoice).destroy!
    missions(:month_end).hints.destroy_all
    missions(:month_end).update!(par_minutes: 90, title: "A different mission", learning_summary: "Changed.")
    tracks(:basics).update!(title: "A different track")

    assert_equal before, result(attempt.reload)
    assert_equal attempt.score, attempt.scorecard.total
    assert attempt.scorecard.mission.readonly?
    assert attempt.scorecard.messages.all? { |entry| entry.message.readonly? }
  end

  test "a copy taken under an older schema still loads: removed columns are dropped and new ones take their defaults" do
    captured = MissionAttempt::ContentSnapshot.capture(missions(:month_end))
    captured["retired_column"] = "gone"
    captured.delete("persona")
    captured["messages"].each { |message| message.delete("needs") }

    mission = MissionAttempt::ContentSnapshot.new(captured).mission
    assert_equal({}, mission.persona)
    assert mission.messages.all? { |message| message.needs == [] }
    assert_not mission.has_attribute?(:retired_column)
  end

  test "a finished attempt builds its scorecard once" do
    attempt = MissionAttempt.start(user: users(:one), mission: missions(:month_end))
    attempt.stand_down

    assert_same attempt.scorecard, attempt.scorecard
    assert_not_same attempt.scorecard, attempt.reload.scorecard
  end

  test "the captured graph resolves story links and private details without querying live messages" do
    mission = missions(:site_visit)
    snapshot = MissionAttempt::ContentSnapshot.new(MissionAttempt::ContentSnapshot.capture(mission)).mission
    mission.messages.destroy_all

    question = snapshot.messages.find { |message| message.key == "sam_text" }
    assert_equal "laptop_text", question.answer_source.key
    assert_equal snapshot, question.mission
    red_flag = snapshot.messages.find { |message| message.key == "it_chat" }.red_flags.find(&:contradicts_key)
    assert_equal "laptop_text", red_flag.contradicted_message.key
    assert_equal mission.persona, snapshot.persona
  end

  private
    def result(attempt)
      card = attempt.scorecard
      [ card.total, card.stars, card.hint_penalty, card.best_possible, card.mission.title, card.mission.track.title,
        card.mission.learning_summary, card.messages.map { |entry| [ entry.message.body_html, entry.points, entry.outcome ] } ]
    end
end
