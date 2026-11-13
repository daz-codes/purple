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

  test "sharing everything, or whatever's asked, never pays; sharing nothing earns fewer stars than careful play" do
    messages(:real_invoice).update!(needs: %w[ staff_number ])
    messages(:fake_invoice).update!(wants: %w[ staff_number memorable_word ])
    lazy = Shift::LazyPlay.new(shifts(:month_end))

    assert lazy.careful.perfect?
    Shift::LazyPlay::DETAIL_STRATEGIES.each do |strategy|
      assert_equal 0, lazy.scorecard(strategy).stars, strategy
    end
    assert_operator lazy.scorecard(:share_nothing).stars, :<, lazy.careful.stars
    assert lazy.scorecard(:share_whatever_asked).message_result_for("fake_invoice").compromised?
    assert_empty lazy.exploits
  end

  test "sharing nothing is an exploit when what needs details is worth too little" do
    messages(:newsletter).update!(expects: "reply", needs: %w[ name ], points: 2,
      replies: [ { "id" => "r1", "text" => "OK", "outcome" => "safe" }, { "id" => "r2", "text" => "Why?", "outcome" => "ask_why", "response" => "Because." } ])
    messages(:fake_invoice).update!(wants: %w[ name ])

    assert_includes Shift::LazyPlay.new(shifts(:month_end)).exploits.keys, :share_nothing
  end
end
