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

  test "stars ignore the speed bonus, and the score is shown out of the best possible including it" do
    # Approve the invoice and archive the newsletter only, very fast: 50 of 105 from messages, so one
    # star; with the bonus counted it would be two.
    card = scorecard(action("use_portal", "real_invoice"), archive("newsletter"), archive("real_invoice"),
      archive("fake_invoice"), archive("supplier_thanks"), elapsed: 0, cleared: true)

    assert_operator card.total, :>=, 105 * 0.6
    assert_equal 1, card.stars
    assert_equal 105 + 40, card.best_possible
    assert_equal 105, scorecard(relaxed: true).best_possible
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

    # Everything right but the sign-in: 55 of 105 from the messages (the speed bonus doesn't count).
    compromised = scorecard(*careful_play, action("click_link", "fake_invoice", result: { "link" => "l1" }),
      action("submit_credentials", "fake_invoice", result: { "link" => "l1" }), elapsed: 0, cleared: true)
    assert compromised.compromised?
    assert_equal 1, compromised.stars

    # However well the rest went, a compromise caps it at two stars.
    compromised.define_singleton_method(:total) { 105 }
    assert_equal 2, compromised.stars
  end

  test "messages are listed in the order they arrived, then any that never did" do
    card = scorecard(archive("real_invoice"))

    assert_equal %w[ real_invoice newsletter fake_invoice supplier_thanks ], card.messages.map { |result| result.message.key }
    assert_equal [ 0, 0, 0, 0 ], card.messages.map(&:arrived_at)

    assert_equal %w[ real_invoice newsletter fake_invoice supplier_thanks ], scorecard.messages.map { |result| result.message.key }
    assert_nil scorecard.message_result_for("fake_invoice").arrived_at
  end

  test "a message that needs details is only done once it has them all, through the right channel" do
    messages(:real_invoice).update!(needs: %w[ staff_number memorable_word ])
    staff, word = share("staff_number", "internal"), share("memorable_word", "secret")

    assert_equal :done, judged(scorecard(shared("real_invoice", "page", staff, word, at: 30), action("use_portal", "real_invoice", at: 30)), "real_invoice").first
    assert_equal :not_done, judged(scorecard(shared("real_invoice", "page", staff), action("use_portal", "real_invoice")), "real_invoice").first
    assert_equal :not_done, judged(scorecard(action("use_portal", "real_invoice")), "real_invoice").first
  end

  test "a genuine message that needs details by reply is done when it gets them; a secret by reply is overshared" do
    messages(:newsletter).update!(expects: "reply", needs: %w[ extension ],
      replies: [ { "id" => "r1", "text" => "OK", "outcome" => "safe" }, { "id" => "r2", "text" => "Why?", "outcome" => "ask_why", "response" => "Because." } ])

    done = scorecard(shared("newsletter", "reply", share("extension", "internal")))
    assert_equal [ :done, 10 ], judged(done, "newsletter")

    over = scorecard(shared("newsletter", "reply", share("extension", "internal"), share("staff_number", "internal"), share("memorable_word", "secret")))
    result = over.message_result_for("newsletter")
    assert_equal %w[ staff_number memorable_word ], result.overshares.map { |share| share["detail"] }
    assert_equal 10 - 5 - 15, result.handling_points
  end

  test "giving a phish anything above public costs 20 or 50 a detail, at most 50, and counts as falling for it" do
    phish = ->(*shares) { scorecard(archive("newsletter"), shared("fake_invoice", "page", *shares)).message_result_for("fake_invoice") }

    assert_equal [ false, 0 ], phish.(share("name", "public")).then { |result| [ result.compromised?, result.detail_points ] }
    assert_equal [ true, -20 ], phish.(share("staff_number", "internal")).then { |result| [ result.compromised?, result.detail_points ] }
    assert_equal(-50, phish.(share("staff_number", "internal"), share("memorable_word", "secret")).detail_points)
    assert_equal [ :compromised ], [ phish.(share("staff_number", "internal")).outcome ]
  end

  test "the MFA code given to a genuine message anywhere but the page that asked for it is a compromise" do
    messages(:real_invoice).update!(needs: %w[ mfa_code ])
    code = share("mfa_code", "never")

    assert_not scorecard(shared("real_invoice", "page", code), action("use_portal", "real_invoice")).compromised?
    misused = scorecard(shared("newsletter", "reply", code))
    assert misused.compromised?
    assert_equal ShiftAttempt::Scorecard::COMPROMISED, misused.message_result_for("newsletter").detail_points
  end

  test "what Red now knows: each detail given to a phish, once" do
    card = scorecard(archive("newsletter"), shared("fake_invoice", "page", share("staff_number", "internal")),
      shared("fake_invoice", "page", share("staff_number", "internal"), share("name", "public")))

    assert_equal %w[ staff_number ], card.leaked_details.map { |share| share["detail"] }
  end

  private
    def share(detail, sensitivity)
      { "chip" => detail, "label" => detail.humanize, "value" => "x", "detail" => detail, "sensitivity" => sensitivity }
    end

    def shared(key, via, *shares, at: 0)
      action("share_details", key, at:, result: { "via" => via, "shared" => shares })
    end

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
