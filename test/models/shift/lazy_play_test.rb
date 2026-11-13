require "test_helper"

class Shift::LazyPlayTest < ActiveSupport::TestCase
  test "no lazy strategy reaches a star, or beats careful play, on either fixture shift" do
    [ shifts(:month_end), shifts(:site_visit) ].each do |shift|
      lazy = Shift::LazyPlay.new(shift)
      careful = lazy.careful

      assert careful.perfect?, "#{shift.slug}: careful play is perfect"
      Shift::LazyPlay::STRATEGIES.each do |strategy|
        card = lazy.scorecard(strategy)
        assert_equal 0, card.stars, "#{shift.slug}: #{strategy} scores #{card.total} of #{card.total_max}"
        assert_operator card.total, :<, careful.total, "#{shift.slug}: #{strategy}"
      end
      assert_empty lazy.exploits
    end
  end

  test "careful play replies with a check-first reply when that's the only good one" do
    messages(:sam_text).update!(replies: [ { "id" => "r1", "text" => "Let me check first", "outcome" => "verify" },
                                           { "id" => "r2", "text" => "No", "outcome" => "poor" } ])

    assert Shift::LazyPlay.new(shifts(:site_visit)).careful.perfect?
  end

  test "reporting everything deals with every message as it arrives, so the speed bonus is in play, scaled by accuracy" do
    card = Shift::LazyPlay.new(shifts(:month_end)).scorecard(:report_everything)

    assert card.cleared?
    assert_equal %i[ reported_wrongly reported_wrongly reported reported_wrongly ], card.messages.map(&:outcome)
    assert_equal 10, card.speed_bonus # 2 blocks under par, times 1 of 4 handled as expected
  end

  test "flagging every sentence finds the quotes in them, and costs far more in wrong flags" do
    card = Shift::LazyPlay.new(shifts(:month_end)).scorecard(:flag_every_sentence_then_report)
    fake = card.message_result_for("fake_invoice")

    assert_equal %w[ pay_today ], fake.found_flags.map(&:key)
    assert_operator card.messages.sum { |result| result.false_flags.size }, :>=, 4
  end
end
