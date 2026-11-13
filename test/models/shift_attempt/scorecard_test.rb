require "test_helper"

# Month-end (par 10 minutes):
#   real_invoice     genuine, expects act (its portal), 40 points, urgent within 10 minutes; at the start
#   newsletter       genuine, expects archive, 10 points; at the start
#   fake_invoice     phish, red flags: the sender (10) and "Please pay today" (10); after one is dealt with
#   supplier_thanks  genuine, expects archive, 5 points; after the real invoice is dealt with
# The best the messages can score is 40 + 10 + 5 + (30 + 20) = 105.
class ShiftAttempt::ScorecardTest < ActiveSupport::TestCase
  setup do
    @shift = shifts(:month_end)
  end

  test "a genuine message is worth its points when the player does what it needed" do
    card = scorecard(action("use_portal", "real_invoice", at: 60), archive("newsletter"))

    assert_equal [ :done, 40 ], judged(card, "real_invoice")
    assert_equal [ :done, 10 ], judged(card, "newsletter")
  end

  test "an urgent message done late earns half, unless the player is in relaxed mode" do
    late = [ action("use_portal", "real_invoice", at: 10 * 60 + 1) ]

    assert_equal [ :done_late, 20 ], judged(scorecard(*late), "real_invoice")
    assert_equal [ :done, 40 ], judged(scorecard(*late, relaxed: true), "real_invoice")
    assert_equal [ :done, 40 ], judged(scorecard(action("use_portal", "real_invoice", at: 10 * 60)), "real_invoice")
  end

  test "a genuine message not done loses half its points, unless it only needed archiving and was left" do
    card = scorecard(archive("real_invoice"))

    assert_equal [ :not_done, -20 ], judged(card, "real_invoice") # archived without approving it
    assert_equal [ :not_done, 0 ], judged(card, "newsletter")     # left in the inbox, but it needed nothing
    assert_equal [ :never_arrived, 0 ], judged(scorecard, "supplier_thanks")
    assert_equal [ :not_done, -20 ], judged(scorecard, "real_invoice") # left in the inbox, and it needed approving
  end

  test "reporting a genuine message costs 15, whatever else was done with it" do
    card = scorecard(action("use_portal", "real_invoice"), action("report_message", "real_invoice"))

    assert_equal [ :reported_wrongly, -15 ], judged(card, "real_invoice")
  end

  test "a reported phish scores 30, and one that never arrived counts for nothing" do
    assert_equal [ :reported, 30 ], judged(scorecard(archive("newsletter"), action("report_message", "fake_invoice")), "fake_invoice")
    assert_equal [ :not_reported, 0 ], judged(scorecard(archive("newsletter"), archive("fake_invoice")), "fake_invoice")
    assert_equal [ :never_arrived, 0 ], judged(scorecard, "fake_invoice")
  end

  test "moves on a message that no longer exists, or hasn't arrived, count for nothing" do
    card = scorecard(action("report_message", "deleted_by_reimport"), action("report_message", "fake_invoice"))

    assert_equal [ :never_arrived, 0 ], judged(card, "fake_invoice")
  end

  test "a compromise costs 50, once per page or file, and a near miss 10" do
    link = { "link" => "l1" }
    compromised = scorecard(archive("newsletter"), action("click_link", "fake_invoice", result: link),
      action("submit_credentials", "fake_invoice", result: link), action("submit_credentials", "fake_invoice", result: link))
    assert_equal [ :compromised, -50 ], judged(compromised, "fake_invoice")

    near = scorecard(archive("newsletter"), action("open_attachment", "fake_invoice", result: { "attachment" => "a1" }))
    assert_equal [ :near_miss, -10 ], judged(near, "fake_invoice")
  end

  test "handing over a code in a chat is a compromise" do
    @shift = shifts(:site_visit)
    card = scorecard(archive("sam_text"), action("send_reply", "it_chat", result: { "outcome" => "compromise", "text" => "Here it is" }))

    assert card.message_result_for("it_chat").gave_in?
    assert_equal [ :compromised, -50 ], judged(card, "it_chat")
  end

  test "a reply counts for a message that expects one, unless it was poor" do
    @shift = shifts(:site_visit)
    good = scorecard(action("send_reply", "sam_text", at: 60, result: { "outcome" => "safe" }), archive("sam_text"))
    poor = scorecard(action("send_reply", "sam_text", result: { "outcome" => "poor" }), archive("sam_text"))

    assert_equal [ :done, 20 ], judged(good, "sam_text")
    assert_equal [ :not_done, -10 ], judged(poor, "sam_text")
  end

  test "red flags: whole parts, quoted phrases found by highlight or sentence, and wrong flags" do
    card = scorecard(archive("newsletter"), flag("fake_invoice", "from"), flag("fake_invoice", "p1", 0, 16),
      flag("fake_invoice", "subject"), action("report_message", "fake_invoice"))
    result = card.message_result_for("fake_invoice")

    assert_equal %w[ lookalike pay_today ], result.found_flags.map(&:key)
    assert_equal [ ShiftAttempt::Flag.new(anchor: "subject", from: nil, to: nil) ], result.false_flags
    assert_equal 30 + 10 + 10 - 10, result.points

    by_sentence = scorecard(archive("newsletter"), flag("fake_invoice", "p1", 0, 17)).message_result_for("fake_invoice")
    assert_equal %w[ pay_today ], by_sentence.found_flags.map(&:key)
  end

  test "a wrong flag costs 10 on a genuine message too, and a flag taken off counts for nothing" do
    card = scorecard(flag("newsletter", "from"), flag("real_invoice", "from"), flag("real_invoice", "from"))

    assert_equal(-10, card.message_result_for("newsletter").flag_points)
    assert_equal 0, card.message_result_for("real_invoice").flag_points
  end

  test "clearing the inbox earns 20 for each full 5 minutes under par, in timed mode only" do
    assert_equal 40, scorecard(*careful_play, elapsed: 0, cleared: true).speed_bonus
    assert_equal 20, scorecard(*careful_play, elapsed: 299, cleared: true).speed_bonus
    assert_equal 20, scorecard(*careful_play, elapsed: 300, cleared: true).speed_bonus
    assert_equal 0, scorecard(*careful_play, elapsed: 301, cleared: true).speed_bonus
    assert_equal 0, scorecard(*careful_play, elapsed: 0, cleared: false).speed_bonus, "clocking off early isn't fast"
    assert_equal 0, scorecard(*careful_play, elapsed: 0, cleared: true, relaxed: true).speed_bonus
  end

  test "the speed bonus is scaled by the share of messages handled as expected" do
    rushed = scorecard(archive("newsletter"), archive("real_invoice"), archive("fake_invoice"), archive("supplier_thanks"),
      elapsed: 0, cleared: true)

    assert_equal 0.5, rushed.accuracy # the newsletter and the thank-you were right; the invoices weren't
    assert_equal 20, rushed.speed_bonus
  end

  test "each hint takes its share of the maximum off the total, which never goes below zero" do
    hint = action("use_hint", nil, result: { "hint" => hints(:month_end_first).position })
    card = scorecard(action("use_portal", "real_invoice"), hint)

    assert_equal 105, card.total_max
    assert_equal [ 21 ], card.hints.map(&:penalty)
    assert_equal 0, scorecard(hint).total
  end

  test "a perfect shift earns three stars; anything less is judged against the maximum, and a compromise caps it at two" do
    perfect = scorecard(action("use_portal", "real_invoice"), archive("newsletter"), flag("fake_invoice", "from"),
      flag("fake_invoice", "p1", 0, 16), action("report_message", "fake_invoice"), archive("real_invoice"), archive("supplier_thanks"))
    assert perfect.perfect?
    assert_equal [ 105, 3 ], [ perfect.total, perfect.stars ]

    # Everything right but the sign-in, plus the full speed bonus: 95, over 90%, but capped at two stars.
    compromised = scorecard(*careful_play, action("click_link", "fake_invoice", result: { "link" => "l1" }),
      action("submit_credentials", "fake_invoice", result: { "link" => "l1" }), elapsed: 0, cleared: true)
    assert compromised.compromised?
    assert_equal 95, compromised.total
    assert_equal 2, compromised.stars
  end

  test "messages are listed in the order they arrived, then any that never did" do
    card = scorecard(archive("real_invoice"))

    assert_equal %w[ real_invoice newsletter fake_invoice supplier_thanks ], card.messages.map { |result| result.message.key }
    assert_equal [ 0, 0, 0, 0 ], card.messages.map(&:arrived_at)

    assert_equal %w[ real_invoice newsletter fake_invoice supplier_thanks ], scorecard.messages.map { |result| result.message.key }
    assert_nil scorecard.message_result_for("fake_invoice").arrived_at
  end

  private
    def careful_play
      [ action("use_portal", "real_invoice"), archive("newsletter"), flag("fake_invoice", "from"), flag("fake_invoice", "p1", 0, 16),
        action("report_message", "fake_invoice"), archive("real_invoice"), archive("supplier_thanks") ]
    end

    def judged(card, key)
      result = card.message_result_for(key)
      [ result.outcome, result.handling_points ]
    end

    def archive(key)
      action("archive_message", key)
    end

    def flag(key, anchor, from = nil, to = nil)
      action("flag_element", key, result: ShiftAttempt::Flag.new(anchor:, from:, to:).to_result)
    end

    def action(kind, target_key, at: 0, penalty: 0, result: {})
      AttemptAction.new(kind:, target_key:, at_seconds: at, penalty_seconds: penalty, result:)
    end

    def scorecard(*actions, elapsed: nil, cleared: false, relaxed: false)
      ShiftAttempt::Scorecard.new(shift: @shift, actions:, elapsed_seconds: elapsed, cleared:, relaxed:)
    end
end
