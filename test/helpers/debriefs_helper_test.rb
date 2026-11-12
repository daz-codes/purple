require "test_helper"

class DebriefsHelperTest < ActionView::TestCase
  include ShiftAttemptsHelper # anchor_label
  setup do
    @shift = shifts(:month_end)
  end

  test "a reported phish is praised" do
    assert_includes story("fake_invoice", action("report_message", "fake_invoice")).join,
      "This was a phish and you reported it. Well done"
  end

  test "running a disguised attachment says what it was, what it did and what to do next time" do
    file = { "attachment" => "a1" }
    result = result("fake_invoice", action("open_attachment", "fake_invoice", result: file), action("run_download", "fake_invoice", result: file))

    assert_equal [ "Phish: you fell for it", :bad ], debrief_verdict(result)
    assert_includes debrief_story(result).join, "You opened Remittance_4471.pdf.exe. It wasn't a document"
    assert_includes debrief_lessons(result).join, "one that ends in .exe is a program"
    assert_includes debrief_verification(result), "Tidemark haven't changed their bank details."
  end

  test "signing in on a lookalike page names the page and explains the padlock" do
    link = { "link" => "l1" }
    result = result("fake_invoice", action("click_link", "fake_invoice", result: link), action("submit_credentials", "fake_invoice", result: link))

    assert_includes debrief_story(result).join, "fake sign-in page at larkhill-portal.example.net"
    assert_includes debrief_lessons(result).join, "A padlock only means the connection is encrypted"
  end

  test "a close call and an unreported phish say what was missed" do
    near = story("fake_invoice", action("click_link", "fake_invoice", result: { "link" => "l1" }))
    assert_includes near.join, "closed it without signing in. A close call"
    assert_includes near.join, "You didn't report it."

    assert_includes story("fake_invoice").join, "You never opened it"
  end

  test "reporting a genuine message explains the cost" do
    assert_includes story("real_invoice", action("report_message", "real_invoice")).join,
      "This was genuine, but you reported it. False alarms cost the security team time, and it was the email you needed for “Approve invoice”."
  end

  test "the headline sums up the shift" do
    assert_equal "You reported 0 of 1 phish, spotted 0 of 1 red flag, and finished 0 of 1 task on time.", debrief_headline(scorecard)
    assert_match "A perfect shift", debrief_headline(scorecard(action("complete_task", "pay_supplier", minute: 1),
      action("flag_element", "fake_invoice", result: { "anchor" => "from" }), action("report_message", "fake_invoice")))
  end

  test "the timeline describes each action, and marks the ones that mattered" do
    card = scorecard
    assert_equal [ 3, "Reported “URGENT invoice”", :good ], debrief_timeline_entry(action("report_message", "fake_invoice", minute: 3), card)
    assert_equal [ 4, "Ran Remittance_4471.pdf.exe: compromised", :bad ],
      debrief_timeline_entry(action("run_download", "fake_invoice", minute: 4, result: { "attachment" => "a1" }), card)
    assert_equal [ 5, "Completed “Approve invoice”", :good ], debrief_timeline_entry(action("complete_task", "pay_supplier", minute: 5), card)
  end

  test "the headline counts wrong flags and hints" do
    hint = action("use_hint", nil, result: { "hint" => @shift.hints.first.position })
    headline = debrief_headline(scorecard(action("flag_element", "real_invoice", result: { "anchor" => "p1" }), hint))

    assert_match "flagged 1 part that wasn't a red flag", headline
    assert_match "took 1 hint", headline
  end

  test "the headline leaves out what the shift didn't have" do
    messages(:fake_invoice).destroy!
    assert_equal "You finished 0 of 1 task on time.", debrief_headline(scorecard)
  end

  test "a message that arrived after the shift ended says so" do
    card = ShiftAttempt::Scorecard.new(shift: @shift, actions: [], clock_minutes: 1)

    assert_equal [ "Phish: arrived after you left", :warn ], debrief_verdict(card.message_result_for("fake_invoice"))
    assert_match "after you'd ended your shift", debrief_story(card.message_result_for("fake_invoice")).join
  end

  test "a compromise through a link that a re-import removed still has a story" do
    compromise = action("run_download", "fake_invoice", result: { "link" => "l9" })

    assert_match "since been changed", story("fake_invoice", compromise).join
  end

  test "the timeline tells a flag from taking it off" do
    flag = action("flag_element", "fake_invoice", result: { "anchor" => "from" })
    entries = debrief_timeline([ flag, flag ], scorecard).map(&:second)

    assert_equal [ "Flagged the sender in “URGENT invoice”", "Took the flag off the sender in “URGENT invoice”" ], entries
  end

  test "red flags show whether they were found, and wrong flags are called out" do
    result = result("fake_invoice", action("flag_element", "fake_invoice", result: { "anchor" => "p1" }))

    assert_equal [ [ "from", false ] ], debrief_red_flags(result).map { |flag, found| [ flag.anchor, found ] }
    assert_equal "You also flagged paragraph 1, which wasn't a giveaway (−10).", debrief_false_flags(result)
    assert_equal "You flagged the sender, but this email was genuine (−10).",
      debrief_false_flags(result("real_invoice", action("flag_element", "real_invoice", result: { "anchor" => "from" })))
  end

  test "handing over a code in a chat says what was sent, what it cost and what to do next time" do
    @shift = shifts(:site_visit)
    sent = action("send_reply", "it_chat", minute: 4, result: { "reply" => "r1" })
    result = result("it_chat", sent)

    assert_equal [ "Phish: you fell for it", :bad ], debrief_verdict(result)
    assert_includes debrief_story(result).join, "You replied “Here it is: 482 913”, handing over exactly what they asked for"
    assert_includes debrief_lessons(result).join, "Never share a one-time code"
    assert_equal [ 4, "Replied “Here it is: 482 913” to “IT Support (Larkhill)”", :bad ], debrief_timeline_entry(sent, scorecard(sent))
  end

  test "refusing, or checking with someone you trust, is called out as the right move" do
    @shift = shifts(:site_visit)
    assert_includes story("it_chat", action("send_reply", "it_chat", result: { "reply" => "r2" })).join, "gave them nothing they could use"

    checked = result("it_chat", action("send_reply", "it_chat", result: { "reply" => "r3" }), action("verify_sender", "it_chat"))
    assert_equal "You checked with someone you already trust: “The IT service desk says that isn't them.”", debrief_verification(checked)
  end

  test "texts and chats are called what they are" do
    @shift = shifts(:site_visit)
    sam = result("sam_text", action("flag_element", "sam_text", result: { "anchor" => "p1" }))
    assert_includes debrief_false_flags(sam), "but this text was genuine"
    assert_equal [ "Text message", "Workchat" ], [ messages(:sam_text), messages(:it_chat) ].map { |message| channel_label(message) }
  end

  test "points are signed" do
    assert_equal [ "+30", "−10", "0" ], [ 30, -10, 0 ].map { |points| debrief_points(points) }
  end

  private
    def action(kind, target_key, minute: 0, result: {})
      AttemptAction.new(kind:, target_key:, minute:, cost_minutes: 0, result:)
    end

    def scorecard(*actions)
      ShiftAttempt::Scorecard.new(shift: @shift, actions:)
    end

    def result(key, *actions)
      scorecard(*actions).message_result_for(key)
    end

    def story(key, *actions)
      debrief_story(result(key, *actions))
    end
end
