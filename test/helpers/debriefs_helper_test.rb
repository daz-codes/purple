require "test_helper"

class DebriefsHelperTest < ActionView::TestCase
  include ShiftAttemptsHelper # flag_label, channel names

  setup do
    @shift = shifts(:month_end)
  end

  test "a reported phish is praised" do
    assert_includes story("fake_invoice", archive("newsletter"), action("report_message", "fake_invoice")).join,
      "This was a phish and you reported it. Well done"
  end

  test "running a disguised attachment says what it was, that nothing seemed to happen, and what to do next time" do
    file = { "attachment" => "a1" }
    result = result("fake_invoice", archive("newsletter"), action("open_attachment", "fake_invoice", result: file),
      action("run_download", "fake_invoice", result: file))

    assert_equal [ "Phish: you fell for it", :bad ], debrief_verdict(result)
    assert_includes debrief_story(result).join, "You opened Remittance_4471.pdf.exe. Nothing seemed to happen, but it wasn't a document"
    assert_includes debrief_lessons(result).join, "one that ends in .exe is a program"
    assert_includes debrief_verification(result), "Tidemark haven't changed their bank details."
  end

  test "signing in on a lookalike page names the page, and that it only said submitted" do
    link = { "link" => "l1" }
    result = result("fake_invoice", archive("newsletter"), action("click_link", "fake_invoice", result: link),
      action("submit_credentials", "fake_invoice", result: link))

    assert_includes debrief_story(result).join, "fake sign-in page at larkhill-portal.example.net. It just said “submitted”"
    assert_includes debrief_lessons(result).join, "A padlock only means the connection is encrypted"
  end

  test "an archived phish says it should have been reported" do
    assert_includes story("fake_invoice", archive("newsletter"), archive("fake_invoice")).join, "You archived it without reporting it."
  end

  test "a genuine message says what it needed, and whether the player did it" do
    assert_includes story("real_invoice", action("use_portal", "real_invoice")).join,
      "This was genuine and needed you to “Approve invoice” through its link. You did it, through its link."
    assert_includes story("real_invoice", archive("real_invoice")).join, "but you archived it without doing that (−20)"
    assert_includes story("newsletter").join, "It was still in your inbox when you stopped, which costs nothing"
    assert_includes story("real_invoice").join, "it was still in your inbox when you stopped (−20)"
    assert_includes story("real_invoice", action("report_message", "real_invoice")).join, "but you reported it. False alarms"
  end

  test "an urgent message done late says how long it took" do
    result = result("real_invoice", action("use_portal", "real_invoice", at: 13 * 60 + 5))

    assert_equal [ "Genuine: dealt with, but late", :warn ], debrief_verdict(result)
    assert_includes debrief_story(result).join, "within 10 minutes of arriving, and you took 13 min 05 s, so it earns half"
  end

  test "a message still to come says so" do
    assert_equal [ "Phish: still to come when you stopped", :neutral ], debrief_verdict(result("fake_invoice"))
    assert_includes story("supplier_thanks").join, "This was still on its way when you stopped."
  end

  test "replies: handing over a code, refusing, or replying poorly to a genuine message" do
    @shift = shifts(:site_visit)
    gave = result("it_chat", archive("sam_text"), reply("it_chat", "compromise", "Here it is: 482 913"))
    assert_includes debrief_story(gave).join, "You replied “Here it is: 482 913”, handing over exactly what they asked for"
    assert_includes debrief_lessons(gave).join, "Never share a one-time code"

    refused = result("it_chat", archive("sam_text"), reply("it_chat", "safe", "No."))
    assert_includes debrief_story(refused).join, "gave them nothing they could use"

    poor = result("sam_text", reply("sam_text", "poor", "Sorry, no time today"), archive("sam_text"))
    assert_includes debrief_story(poor).join, "your reply, “Sorry, no time today”, didn't do what it asked"
  end

  test "a question says where its answer was, whether or not the player found it" do
    @shift = shifts(:site_visit)
    right = result("sam_text", reply("sam_text", "safe", "Sure, see you there"), archive("sam_text"))
    assert_equal "You'd read carefully: the answer was in Larkhill IT's text: “ready to collect on Thursday”.", debrief_answer_source(right)

    wrong = result("sam_text", reply("sam_text", "poor", "Sorry, no time today"), archive("sam_text"))
    assert_match(/\AThe answer was in Larkhill IT's text: “ready to collect on Thursday”\. Messages often hold details/, debrief_answer_source(wrong))

    assert_nil debrief_answer_source(result("laptop_text", archive("laptop_text")))
  end

  test "a red flag that contradicts an earlier message quotes it" do
    assert_equal "Earlier, Larkhill IT told you: “We never ask for codes”", debrief_contradiction(red_flags(:code_request))
    assert_nil debrief_contradiction(red_flags(:pay_today))
  end

  test "the headline sums up the shift" do
    assert_equal "You reported 0 of 1 phish, dealt with 0 of 3 genuine messages, and spotted 0 of 2 red flags.", debrief_headline(scorecard)
  end

  test "the timeline describes each move with its time, and marks the ones that mattered" do
    card = scorecard
    assert_equal [ 65, "Reported “URGENT invoice”", :good ], debrief_timeline_entry(action("report_message", "fake_invoice", at: 65), card)
    assert_equal [ 70, "Called the sender of “Invoice ready” back (+30 s)", :neutral ],
      debrief_timeline_entry(action("verify_sender", "real_invoice", at: 70, penalty: 30), card)
    assert_equal [ 5, "Archived “Invoice ready”", :warn ], debrief_timeline_entry(archive("real_invoice", at: 5), card)
    assert_equal "1:05", debrief_clock(65)
  end

  test "the timeline tells a flag from taking it off, and names highlighted words" do
    on = flag("fake_invoice", "p1", 0, 16)
    entries = debrief_timeline([ archive("newsletter"), on, on ], scorecard(archive("newsletter"), on, on))

    assert_equal "Flagged “Please pay today” in “URGENT invoice”", entries[1][1]
    assert_equal "Took the flag off “Please pay today” in “URGENT invoice”", entries[2][1]
  end

  test "red flags show whether they were found, and wrong flags are called out" do
    result = result("fake_invoice", archive("newsletter"), flag("fake_invoice", "from"), flag("fake_invoice", "subject"))

    assert_equal [ [ "lookalike", true ], [ "pay_today", false ] ], debrief_red_flags(result).map { |red_flag, found| [ red_flag.key, found ] }
    assert_equal "You also flagged the subject, which wasn't a giveaway (−10).", debrief_false_flags(result)
  end

  test "the message's text is marked with the player's highlights and the giveaways" do
    result = result("fake_invoice", archive("newsletter"), flag("fake_invoice", "p1", 18, 21))
    paragraphs = debrief_marked_paragraphs(result)

    assert_equal [ "Please pay today", "#{DebriefsHelper::MARK_CLASSES[:missed]} bg-transparent" ], paragraphs.first[0]
    assert_equal [ "Our", DebriefsHelper::MARK_CLASSES[:wrong] ], paragraphs.first[2]
    assert_empty debrief_marked_paragraphs(result("newsletter"))
  end

  test "how the shift ended" do
    attempt = ShiftAttempt.start(user: users(:one), shift: @shift)
    attempt.clock_off

    assert_match(/\AYou clocked off after \d+ s\./, debrief_ending(attempt, attempt.scorecard))
  end

  test "points and durations read naturally" do
    assert_equal [ "+30", "−10", "0" ], [ 30, -10, 0 ].map { |points| debrief_points(points) }
    assert_equal [ "45 s", "7 min 05 s" ], [ 45, 425 ].map { |seconds| debrief_duration(seconds) }
  end

  private
    def action(kind, target_key, at: 0, penalty: 0, result: {})
      AttemptAction.new(kind:, target_key:, at_seconds: at, penalty_seconds: penalty, result:)
    end

    def archive(key, at: 0)
      action("archive_message", key, at:)
    end

    def reply(key, outcome, text)
      action("send_reply", key, result: { "outcome" => outcome, "text" => text })
    end

    def flag(key, anchor, from = nil, to = nil)
      action("flag_element", key, result: ShiftAttempt::Flag.new(anchor:, from:, to:).to_result)
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
