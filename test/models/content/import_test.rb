require "test_helper"

class Content::ImportTest < ActiveSupport::TestCase
  # --- The content shipped in content/ ---------------------------------------------------

  test "the shipped content imports cleanly" do
    summary = Content::Import.new.run

    assert_operator summary.techniques, :>=, 12
    assert_equal 9, summary.badges
    assert_equal 3, summary.tracks
    assert_operator summary.shifts, :>=, 4
  end

  test "importing twice changes nothing" do
    Content::Import.new.run
    before = snapshot

    Content::Import.new.run

    assert_equal before, snapshot
  end

  test "every shipped shift meets the starter content rules" do
    Content::Import.new.run

    Shift.where(slug: shipped_shift_slugs).each do |shift|
      messages = shift.messages.includes(:red_flags)
      assert_includes 5..12, messages.size, "#{shift.slug} should have 5-12 messages"
      assert messages.any? { |message| message.expects_reply? || message.expects_act? }, "#{shift.slug} needs a genuine message to reply to or act on"
      assert messages.any?(&:arrives_after), "#{shift.slug} needs a follow-up"
      assert messages.any? { |message| message.red_flags.any?(&:quote?) }, "#{shift.slug} needs a quoted red flag"
      assert messages.any? { |message| message.red_flags.any?(&:contradicts_key) }, "#{shift.slug} needs a red flag that contradicts an earlier message"
      assert messages.any?(&:answer_in_key), "#{shift.slug} needs a question answered by an earlier message"
      assert shift.persona.present?, "#{shift.slug} needs a persona"
      assert messages.any? { |message| message.legit? && message.needs.any? }, "#{shift.slug} needs a genuine message that needs a detail"
      assert messages.any? { |message| message.phish? && message.wants.any? }, "#{shift.slug} needs a phish that wants a detail"
      assert shift.directory.any?, "#{shift.slug} needs a staff directory"
    end
    assert_equal 3, Shift.where(slug: shipped_shift_slugs).kind_inbox.count
    assert_equal 1, Shift.where(slug: shipped_shift_slugs).kind_messages.count
    shipped = Message.joins(:shift).where(shifts: { slug: shipped_shift_slugs })
    assert shipped.any? { |message| message.details.any? }, "a shift needs a detail learned from a message"
    assert shipped.joins(:techniques).exists?(techniques: { key: "mfa_fatigue" }), "a shift needs an MFA-fatigue run"
  end

  # --- A minimal content folder, mutated one rule at a time ------------------------------

  setup do
    @root = Pathname(Dir.mktmpdir("content"))
    @shift = valid_shift
  end

  teardown { FileUtils.remove_entry(@root) }

  test "imports a valid shift with neutral ids and hidden answers stored server-side" do
    import!
    shift = Shift.find_by!(slug: "month-end")
    real = shift.messages.find_by!(key: "real_invoice")
    fake = shift.messages.find_by!(key: "fake_invoice")

    assert shift.published?
    assert_equal 10, shift.par_minutes
    assert_equal [ "act", 40, 10, true ], [ real.expects, real.points, real.urgent_within_minutes, real.arrives_at_start? ]
    assert_equal [ "portal", "portal", "Approve invoice" ], real.links.sole.then { |link| [ link.outcome, link.landing_template, link.portal_action ] }
    assert_equal [ nil, 0, 1 ], [ fake.expects, fake.points, fake.arrives_after_handled ]
    assert_equal "credential_harvest", fake.links.sole.landing_template
    assert_equal %w[ lookalike_domain ], fake.techniques.pluck(:key)
    assert_equal [ [ "l1", nil, nil ], [ "from", nil, nil ], [ "p1", 0, 16 ] ], fake.red_flags.reorder(:key).pluck(:anchor, :quote_start, :quote_end)
    assert_includes fake.body_html, %(data-link-key="l1")
    assert_includes fake.body_html, %(data-anchor="p1s2")
    assert_not_includes fake.body_html, "href"
  end

  test "a persona and staff directory are stored on the shift" do
    @shift["persona"] = { "name" => "Robin Ashby", "role" => "Accounts clerk", "staff_prefix" => "LH",
                          "security_question" => "Name of the office dog?" }
    @shift["directory"] = [ { "name" => "IT service desk", "team" => "IT", "contact" => "Ext 4400" }, { "name" => "Reception", "contact" => "Ext 4000" } ]
    import!
    shift = Shift.find_by!(slug: "month-end")

    assert_equal "LH", shift.persona["staff_prefix"]
    assert_equal [ { "name" => "IT service desk", "team" => "IT", "contact" => "Ext 4400" }, { "name" => "Reception", "contact" => "Ext 4000" } ],
      shift.directory
  end

  test "a shift without a persona or directory imports with neither" do
    import!

    assert_equal [ {}, [] ], Shift.find_by!(slug: "month-end").then { |shift| [ shift.persona, shift.directory ] }
  end

  test "persona rules: a short capital prefix, a real question, fiction only" do
    persona = { "name" => "Robin Ashby", "role" => "Clerk", "staff_prefix" => "LH", "security_question" => "Name of the office dog?" }

    @shift["persona"] = persona.merge("staff_prefix" => "lh-1")
    assert_import_error "staff_prefix must be 2-3 capital letters"

    @shift["persona"] = persona.merge("security_question" => "The office dog")
    assert_import_error "must be a question"

    @shift["persona"] = persona.merge("role" => "Clerk at https://bank.com")
    assert_import_error "role mentions names outside the reserved fictional set"

    @shift["persona"] = persona.merge("password" => "hunter2")
    assert_import_error "unknown key password"
  end

  test "the directory says how to reach someone, never an email address" do
    @shift["directory"] = [ { "name" => "IT", "contact" => "servicedesk@larkhill.example" } ]

    assert_import_error "not an email address"
  end

  test "arrivals: after a count, or after another message, with phishes following up too" do
    @shift["messages"] << newsletter.merge("arrives" => { "after" => "real_invoice" })
    @shift["messages"] << @shift["messages"][2].deep_dup.merge("key" => "fake_chaser", "arrives" => { "after" => "fake_invoice" })
    import!

    assert_equal "real_invoice", Message.find_by!(key: "newsletter").arrives_after
    assert_equal "fake_invoice", Message.find_by!(key: "fake_chaser").arrives_after
  end

  test "a fake may imitate a message it arrives with" do
    @shift["messages"].last.merge!("imitates" => "real_invoice", "arrives" => "start")
    assert_nothing_raised { import! }

    @shift["messages"].first["arrives"] = { "after_handled" => 1 }
    @shift["messages"].last["arrives"] = { "after_handled" => 1 }
    assert_nothing_raised { import! }
  end

  test "a red flag can contradict an earlier genuine message, and a question can say where its answer was" do
    with_story(@shift)
    import!

    flag = Message.find_by!(key: "fake_invoice").red_flags.find_by!(key: "pay_today")
    assert_equal [ "canteen_news", "Tidemark invoices only ever come through the portal" ], [ flag.contradicts_key, flag.contradicts_quote ]
    assert_equal "canteen_news", flag.contradicted_message.key

    question = Message.find_by!(key: "lunch_question")
    assert_equal [ "canteen_news", "Room 4B" ], [ question.answer_in_key, question.answer_in_quote ]
    assert_equal "canteen_news", question.answer_source.key
    assert_not_includes question.body_html, "canteen_news"
  end

  test "a question can follow its answer through a chain of after: triggers, or be answered by a phish if it comes last" do
    with_story(@shift)
    @shift["messages"][1]["arrives"] = { "after" => "real_invoice" }
    @shift["messages"].last["arrives"] = { "after" => "canteen_news" }
    @shift["messages"][2]["red_flags"].last.delete("contradicts")
    @shift["messages"] << @shift["messages"][2].deep_dup.merge("key" => "fake_chaser", "arrives" => { "after" => "fake_invoice" })
    @shift["messages"] << @shift["messages"][2].deep_dup.merge("key" => "fake_chaser_two", "arrives" => { "after" => "fake_chaser" })
    assert_nothing_raised { import! }

    with_story(@shift = valid_shift)
    @shift["messages"].last.merge!("answer_in" => { "message" => "fake_invoice", "quote" => "Our bank details have changed" },
                                   "arrives" => { "after_handled" => 3 })
    assert_nothing_raised { import! }
  end

  test "rejects broken story links" do
    {
      "an answer in a message that isn't there" => [ ->(s) { s["messages"].last["answer_in"]["message"] = "nope" },
                                                     /answer_in: message "nope" isn't another message in this shift/ ],
      "an answer in the question itself" => [ ->(s) { s["messages"].last["answer_in"]["message"] = "lunch_question" },
                                              /message "lunch_question" isn't another message/ ],
      "a quote the source doesn't have" => [ ->(s) { s["messages"].last["answer_in"]["quote"] = "Room 9Z" },
                                             /quote "Room 9Z" must appear exactly once in canteen_news \(found 0\)/ ],
      "a question that could come before its answer" => [
        ->(s) { s["messages"][1]["arrives"] = { "after_handled" => 1 }; s["messages"].last["arrives"] = "start"
                s["messages"][2]["red_flags"].last.delete("contradicts") },
        /lunch_question could arrive before canteen_news/ ],
      "a contradiction that could come first" => [
        ->(s) { s["messages"][1]["arrives"] = { "after_handled" => 1 }; s["messages"][2]["arrives"] = "start" },
        /fake_invoice could arrive before canteen_news/ ],
      "an answer in a phish, asked mid-shift" => [ ->(s) { s["messages"].last["answer_in"] = { "message" => "fake_invoice", "quote" => "Please pay today" } },
                                                    /the answer is in a phish, so lunch_question must arrive last \(arrives: \{ after_handled: 3 \}\)/ ],
      "contradicting a phish" => [
        ->(s) { s["messages"] << s["messages"][2].deep_dup.merge("key" => "fake_two", "arrives" => "start")
                s["messages"].last["red_flags"].last["contradicts"] = { "message" => "fake_invoice", "quote" => "Our bank details have changed" } },
        /contradicts must point at a genuine message/ ],
      "a question on a phish" => [ ->(s) { s["messages"][2]["answer_in"] = { "message" => "canteen_news", "quote" => "Room 4B" } },
                                   /answer_in is only for genuine messages that expect a reply/ ],
      "a question with no wrong answer" => [ ->(s) { s["messages"].last["replies"].last["outcome"] = "safe" },
                                             /answer_in needs a wrong answer among the replies \(outcome: poor\)/ ],
      "a story link that isn't a hash" => [ ->(s) { s["messages"].last["answer_in"] = "canteen_news" },
                                            /answer_in must be \{ message: other_key, quote: "the words" \}/ ],
      "an unknown story link key" => [ ->(s) { s["messages"].last["answer_in"]["line"] = 2 }, /unknown key line/ ]
    }.each do |description, (mutate, message)|
      @shift = with_story(valid_shift)
      mutate.call(@shift)

      error = assert_raises(Content::ImportError, "expected an error for #{description}") { import! }
      assert_match message, error.message, "wrong error for #{description}"
    end
  end

  test "quotes are matched on the text as the player sees it: whitespace runs count as one space" do
    @shift["messages"].last["body_html"] = @shift["messages"].last["body_html"].sub("Please pay today.", "Please   pay\n  today.")
    @shift["messages"].last["red_flags"].last["quote"] = "Please pay today"
    import!

    assert_equal [ 0, 16 ], Message.find_by!(key: "fake_invoice").red_flags.find_by!(key: "pay_today").then { |flag| [ flag.quote_start, flag.quote_end ] }
  end

  test "updates records in place and removes children that were deleted from the file" do
    import!
    message_id = Message.find_by!(key: "fake_invoice").id

    @shift["messages"].last["subject"] = "Changed subject"
    @shift["messages"].last["red_flags"].pop
    @shift["hints"] = []
    import!

    message = Message.find(message_id)
    assert_equal "Changed subject", message.subject
    assert_equal %w[ lookalike link_mismatch ], message.red_flags.pluck(:key)
    assert_empty Shift.find_by!(slug: "month-end").hints
  end

  test "unpublishes shifts whose file has gone, keeping the record" do
    import!
    FileUtils.rm(@root.join("tracks/basics/month-end.yml"))
    write_yaml("tracks/basics/other.yml", valid_shift.merge("slug" => "other"))
    Content::Import.new(@root).run

    assert_not Shift.find_by!(slug: "month-end").published?
    assert Shift.find_by!(slug: "other").published?
  end

  test "a failed import changes nothing" do
    import!
    @shift["title"] = "A new title"
    @shift["messages"].last["techniques"] = [ "made_up" ]

    assert_raises(Content::ImportError) { import! }
    assert_equal "Month-end", Shift.find_by!(slug: "month-end").title
  end

  test "errors name the file and the location" do
    @shift["messages"].last["links"].first["outcome"] = "portal"

    error = assert_raises(Content::ImportError) { import! }
    assert_match %r{\Acontent[\w-]*/tracks/basics/month-end\.yml: messages\[2\] \(fake_invoice\) → links\[0\]: }, error.message
  end

  test "rejects bad content" do
    {
      "unknown keys" => [ ->(s) { s["colour"] = "red" }, /unknown key colour/ ],
      "slug not matching the file" => [ ->(s) { s["slug"] = "other" }, /must match the file name/ ],
      "a non-reserved link" => [ ->(s) { s["messages"].first["body_html"] = %(<p><a href="https://larkhill.com/x">x</a></p>) },
                                 /isn't an http\(s\) URL on a reserved fictional domain/ ],
      "a real sender address" => [ ->(s) { s["messages"].first["from_address"] = "accounts@tidemark.com" },
                                   /from_address "accounts@tidemark.com" must be a fictional address/ ],
      "a real domain in the subject" => [ ->(s) { s["messages"].first["subject"] = "Pay at tidemark.com" },
                                          /subject mentions names outside the reserved fictional set/ ],
      "an author-supplied id" => [ ->(s) { s["messages"].first["body_html"] = %(<p id="flag-urgency">x</p>) },
                                   /attribute id="flag-urgency"/ ],
      "a missing anchor" => [ ->(s) { s["messages"].last["red_flags"].first["anchor"] = "a9" },
                              /anchor "a9" doesn't exist in this message/ ],
      "a descriptive anchor" => [ ->(s) { s["messages"].last["red_flags"].first["anchor"] = "flag-urgency" },
                                  /anchor "flag-urgency" doesn't exist/ ],
      "a paragraph as a red flag" => [ ->(s) { s["messages"].last["red_flags"].first["anchor"] = "p1" },
                                       /anchor "p1" doesn't exist .*Body text is flagged with quote/ ],
      "reply_to anchor without a reply_to" => [ ->(s) { s["messages"].last["red_flags"].first["anchor"] = "reply_to" },
                                                /anchor "reply_to" doesn't exist/ ],
      "a quote that isn't in the body" => [ ->(s) { s["messages"].last["red_flags"].last["quote"] = "Pay tomorrow" },
                                            /quote "Pay tomorrow" must appear exactly once \(found 0\)/ ],
      "a quote found more than once" => [ ->(s) { s["messages"].last["red_flags"].last["quote"] = "a" },
                                          /quote "a" must appear exactly once \(found \d+\)/ ],
      "a quote in the wrong paragraph" => [ ->(s) { s["messages"].last["red_flags"].last["in"] = "p2" },
                                            /quote "Please pay today" must appear exactly once in p2 \(found 0\)/ ],
      "a quote in an unknown paragraph" => [ ->(s) { s["messages"].last["red_flags"].last["in"] = "p9" }, /in: "p9" isn't a paragraph/ ],
      "a red flag with an anchor and a quote" => [ ->(s) { s["messages"].last["red_flags"].last["anchor"] = "from" }, /not both/ ],
      "a red flag with neither" => [ ->(s) { s["messages"].last["red_flags"].first.delete("anchor") }, /needs an anchor .* or a quote/ ],
      "a phish with a portal" => [ ->(s) { s["messages"].last["links"].first.merge!("outcome" => "portal", "action" => "Pay") },
                                   /outcome must be one of bait_landing, malware, harmless for phishing messages/ ],
      "a legit message with a bait link" => [ ->(s) { s["messages"].first["links"].first.merge!("outcome" => "bait_landing").delete("action") },
                                              /outcome must be one of portal, harmless for legitimate messages/ ],
      "a portal without its button" => [ ->(s) { s["messages"].first["links"].first.delete("action") }, /action is required when outcome is portal/ ],
      "a button on a link that isn't a portal" => [ ->(s) { s["messages"].last["links"].first["action"] = "Sign in" },
                                                    /action can only be set when outcome is portal/ ],
      "expects act with no portal" => [ ->(s) { s["messages"].first["links"].first.merge!("outcome" => "harmless").delete("action") },
                                        /expects: act needs exactly one portal link to act on \(found 0\)/ ],
      "a portal on a message that doesn't expect act" => [ ->(s) { s["messages"].first["expects"] = "archive" },
                                                           /portal links are only for messages that expect: act/ ],
      "a genuine message that expects nothing" => [ ->(s) { s["messages"].first.delete("expects") }, /expects is required/ ],
      "an unknown expectation" => [ ->(s) { s["messages"].first["expects"] = "pray" }, /expects must be one of reply, act, archive/ ],
      "a genuine message with no points" => [ ->(s) { s["messages"].first.delete("points") }, /points is required/ ],
      "a phish with points" => [ ->(s) { s["messages"].last["points"] = 10 }, /points is only for genuine messages/ ],
      "a phish that's urgent" => [ ->(s) { s["messages"].last["urgent_within_minutes"] = 5 }, /urgent_within_minutes is only for genuine messages/ ],
      "a phish that expects something" => [ ->(s) { s["messages"].last["expects"] = "archive" }, /expects is only for genuine messages/ ],
      "expects a reply with none offered" => [ ->(s) { phone(s)["messages"] << newsletter.merge("channel" => "sms", "expects" => "reply").except("to_address", "subject") },
                                               /expects: reply needs at least one reply that isn't poor/ ],
      "expects a reply with only poor ones" => [
        ->(s) { phone(s)["messages"] << newsletter.merge("channel" => "sms", "expects" => "reply", "replies" => poor_replies).except("to_address", "subject") },
        /expects: reply needs at least one reply that isn't poor/ ],
      "a bad arrival" => [ ->(s) { s["messages"].last["arrives"] = "later" }, /arrives must be start, \{ after_handled: N \} or \{ after: message_key \}/ ],
      "both arrival triggers" => [ ->(s) { s["messages"].last["arrives"] = { "after_handled" => 1, "after" => "real_invoice" } },
                                   /give exactly one of after_handled or after/ ],
      "an unknown arrival trigger" => [ ->(s) { s["messages"].last["arrives"] = { "at_minute" => 3 } }, /unknown key at_minute/ ],
      "arriving after an unknown message" => [ ->(s) { s["messages"].last["arrives"] = { "after" => "nope" } },
                                               /"fake_invoice" arrives after "nope", which isn't another message/ ],
      "arriving after itself" => [ ->(s) { s["messages"].last["arrives"] = { "after" => "fake_invoice" } },
                                   /"fake_invoice" arrives after "fake_invoice", which isn't another message/ ],
      "a count the shift never reaches" => [ ->(s) { s["messages"].last["arrives"] = { "after_handled" => 3 } },
                                             /fake_invoice can never arrive/ ],
      "nothing at the start" => [ ->(s) { s["messages"].first(2).each { |m| m["arrives"] = { "after" => "fake_invoice" } } },
                                  /at least one message must arrive at the start/ ],
      "a loop" => [ ->(s) { s["messages"].first["arrives"] = { "after" => "fake_invoice" }; s["messages"].last["arrives"] = { "after" => "real_invoice" }; s["messages"] << newsletter },
                    /real_invoice, fake_invoice can never arrive/ ],
      "a fake imitating a message it could arrive after" => [
        ->(s) { s["messages"].last["imitates"] = "real_invoice" },
        /imitates "real_invoice" but could arrive after it: a fake must arrive at the start, or on exactly the same arrives: trigger/ ],
      "a fake imitating a message that isn't there" => [ ->(s) { s["messages"].last.merge!("imitates" => "nope", "arrives" => "start") },
                                                          /imitates "nope", which isn't a genuine message in this shift/ ],
      "a fake imitating another fake" => [ ->(s) { s["messages"].last.merge!("imitates" => "fake_invoice", "arrives" => "start") },
                                           /imitates "fake_invoice", which isn't a genuine message/ ],
      "a genuine message imitating something" => [ ->(s) { s["messages"].first["imitates"] = "canteen_news" },
                                                   /only phishing messages can imitate another message/ ],
      "more genuine follow-ups than phish ones" => [
        ->(s) {
          s["messages"] << newsletter.merge("arrives" => { "after" => "real_invoice" })
          s["messages"] << newsletter.merge("key" => "newsletter_two", "arrives" => { "after" => "canteen_news" })
          s["messages"] << s["messages"][2].deep_dup.merge("key" => "fake_chaser", "arrives" => { "after" => "fake_invoice" })
        },
        /2 genuine messages have follow-up .* but only 1 phish does/ ],
      "a genuine follow-up with no phish follow-up" => [ ->(s) { s["messages"] << newsletter.merge("arrives" => { "after" => "real_invoice" }) },
                                                         /1 genuine message has a follow-up .* but no phish does/ ],
      "a quote across two sentences" => [ ->(s) { s["messages"].last["red_flags"].last["quote"] = "today. Our bank" },
                                          /quote "today. Our bank" crosses from one sentence into the next/ ],
      "lazy play that pays" => [
        ->(s) { s["messages"].delete_at(1); s["messages"].first["points"] = 5; s["messages"] << s["messages"].last.deep_dup.merge("key" => "fake_two") },
        /lazy play scores too well: report everything scores \d+ of 125 \(1 star\)/ ],
      "a link no rule matches" => [ ->(s) { s["messages"].first["links"].first["match"] = "nowhere.example" },
                                    /link l1 \(.*\) matches 0 link rules/ ],
      "a rule matching no link" => [ ->(s) { s["messages"].first["links"] << { "match" => "nowhere.example", "outcome" => "harmless" } },
                                     /match "nowhere.example" doesn't match any link/ ],
      "a mismatched landing" => [ ->(s) { s["messages"].last["links"].first["landing"] = "portal" },
                                  /landing for a bait_landing link must be credential_harvest/ ],
      "an unknown technique" => [ ->(s) { s["messages"].last["techniques"] = [ "made_up" ] }, /unknown technique "made_up"/ ],
      "a phish without techniques" => [ ->(s) { s["messages"].last.delete("techniques") }, /need at least one technique/ ],
      "a phish without red flags" => [ ->(s) { s["messages"].last.delete("red_flags") }, /need at least one red flag/ ],
      "a legit message with red flags" => [ ->(s) { s["messages"].first["red_flags"] = [ s["messages"].last["red_flags"].first.deep_dup ] },
                                            /legitimate messages can't have red flags/ ],
      "no phishing at all" => [ ->(s) { s["messages"].pop }, /needs at least one phishing message/ ],
      "a wrongly typed field" => [ ->(s) { s["par_minutes"] = "ten" }, /par_minutes must be a integer/ ],
      "an unknown kind" => [ ->(s) { s["kind"] = "voice" }, /kind must be one of inbox, messages/ ],
      "an email without a subject" => [ ->(s) { s["messages"].first.delete("subject") }, /subject is required for emails/ ],
      "duplicate message keys" => [ ->(s) { s["messages"].last["key"] = "real_invoice" }, /message keys must be unique/ ],
      "a real domain on an uncommon TLD" => [ ->(s) { s["briefing"] = "Log in at realbank.co.za" },
                                              /briefing mentions names outside the reserved fictional set: realbank\.co\.za/ ],
      "a real domain in the shift title" => [ ->(s) { s["title"] = "Month-end at realbank.com" }, /title mentions names/ ],
      "a real brand in a red flag label" => [ ->(s) { s["messages"].last["red_flags"].first["label"] = "Not really PayPal" },
                                              /label mentions names outside the reserved fictional set: PayPal/ ],
      "a real brand on a portal button" => [ ->(s) { s["messages"].first["links"].first["action"] = "Pay with PayPal" },
                                             /action mentions names outside the reserved fictional set: PayPal/ ],
      "a real brand as an SMS sender" => [ ->(s) { s["messages"].first["from_address"] = "PayPal" },
                                           /from_address "PayPal" must be a fictional address/ ],
      "a repeated technique" => [ ->(s) { s["messages"].last["techniques"] = %w[ lookalike_domain lookalike_domain ] },
                                  /messages\[2\] \(fake_invoice\): technique keys must be unique \(lookalike_domain\)/ ],
      "an attachment on a text" => [ ->(s) { phone(s)["messages"].last["attachments"] = [ { "name" => "a.pdf", "type" => "application/pdf", "size" => "1 KB", "outcome" => "harmless" } ] },
                                     /attachments are only for emails/ ],
      "a single reply" => [ ->(s) { phone(s)["messages"].last["replies"] = chat_replies.first(1) }, /from 2 to 4 options/ ],
      "five replies" => [ ->(s) { phone(s)["messages"].last["replies"] = 5.times.map { |i| { "text" => "Reply #{i}", "outcome" => "safe" } } },
                          /from 2 to 4 options/ ],
      "a reply that hands over on a genuine message" => [
        ->(s) { phone(s)["messages"].first["replies"] = chat_replies },
        /outcome must be one of safe, poor, verify, ask_why for legitimate messages \(got compromise\)/ ],
      "a poor reply on a phish" => [ ->(s) { phone(s)["messages"].last["replies"] = poor_replies },
                                     /outcome must be one of safe, compromise, verify, ask_why for phishing messages \(got poor\)/ ],
      "an unknown reply outcome" => [ ->(s) { phone(s)["messages"].last["replies"] = chat_replies.each { |r| r["outcome"] = "explode" } },
                                      /outcome must be one of safe, compromise, verify/ ],
      "a repeated reply" => [ ->(s) { phone(s)["messages"].last["replies"] = [ chat_replies.first, chat_replies.first ] },
                              /each reply needs different text/ ],
      "a chat in an inbox shift" => [ ->(s) { s["messages"].last["channel"] = "chat" },
                                      /channel must be one of email for inbox shifts \(got chat\)/ ],
      "an email in a messages shift" => [ ->(s) { phone(s)["messages"].last.merge!("channel" => "email", "subject" => "Hi", "to_address" => "you@larkhill.example") },
                                          /channel must be one of sms, chat for messages shifts \(got email\)/ ],
      "a red flag on a text's reply_to, which the phone never shows" => [
        ->(s) { phone(s)["messages"].last.merge!("reply_to" => "x@freemail.test")["red_flags"].first["anchor"] = "reply_to" },
        /anchor "reply_to" doesn't exist/ ],
      "a real brand in a reply" => [ ->(s) { phone(s)["messages"].last["replies"] = chat_replies.each { |r| r["response"] = "Sent from PayPal" } },
                                     /response mentions names outside the reserved fictional set: PayPal/ ]
    }.each do |description, (mutate, message)|
      @shift = valid_shift
      mutate.call(@shift)

      error = assert_raises(Content::ImportError, "expected an error for #{description}") { import! }
      assert_match message, error.message, "wrong error for #{description}"
    end
  end

  test "a text or chat can offer canned replies, with neutral ids and outcomes kept on the server" do
    phone(@shift)["messages"].last["replies"] = chat_replies
    import!

    fake = Message.find_by!(key: "fake_invoice")
    assert_equal %w[ r1 r2 r3 ], fake.replies.map { |reply| reply["id"] }
    assert_equal %w[ compromise safe verify ], fake.replies.map { |reply| reply["outcome"] }
    assert_equal [ { "id" => "r1", "text" => "Here it is: 482 913" } ], fake.visible_replies.first(1)
  end

  test "a legitimate message may list an empty red_flags" do
    @shift["messages"].first["red_flags"] = []
    assert_nothing_raised { import! }
  end

  test "rejects duplicate technique and badge keys" do
    write_content
    techniques = YAML.load_file(@root.join("techniques.yml"))
    techniques["techniques"] << techniques["techniques"].first.merge("name" => "Another")
    write_yaml("techniques.yml", techniques)
    assert_raises(Content::ImportError, match: /techniques\.yml: technique keys must be unique \(lookalike_domain\)/) do
      Content::Import.new(@root).run
    end

    write_content
    badges = YAML.load_file(@root.join("badges.yml"))
    badges["badges"] << badges["badges"].first.merge("name" => "Another")
    write_yaml("badges.yml", badges)
    assert_raises(Content::ImportError, match: /badges\.yml: badge keys must be unique \(first_catch\)/) do
      Content::Import.new(@root).run
    end
  end

  test "checks track, technique and badge text is fictional" do
    write_content
    write_yaml("tracks/basics/_track.yml", valid_track.merge("description" => "Phishing at realbank.com"))
    assert_raises(Content::ImportError, match: %r{_track\.yml: description mentions names}) { Content::Import.new(@root).run }

    write_content
    write_yaml("badges.yml", "badges" => [
      { "key" => "first_catch", "name" => "Netflix Fan", "description" => "Report a phish.", "side" => "blue" }
    ])
    assert_raises(Content::ImportError, match: /badges\[0\] \(first_catch\): name mentions names .*Netflix/) do
      Content::Import.new(@root).run
    end
  end

  test "a missing tracks folder is a friendly error" do
    write_content
    FileUtils.rm_rf(@root.join("tracks"))

    assert_raises(Content::ImportError, match: /no tracks folder found/) { Content::Import.new(@root).run }
  end

  test "the summary counts messages across all shifts" do
    assert_equal 3, import!.messages
  end

  test "rejects invalid YAML with the file name" do
    write_content
    @root.join("tracks/basics/month-end.yml").write("title: [unclosed")

    assert_raises(Content::ImportError, match: %r{month-end\.yml: isn't valid YAML}) { Content::Import.new(@root).run }
  end

  test "rejects a track folder without _track.yml" do
    write_content
    @root.join("tracks/empty").mkpath

    assert_raises(Content::ImportError, match: /tracks\/empty: is missing _track\.yml/) { Content::Import.new(@root).run }
  end

  test "rejects the same shift slug in two tracks" do
    write_content
    write_yaml("tracks/zzz/_track.yml", valid_track)
    write_yaml("tracks/zzz/month-end.yml", valid_shift)

    assert_raises(Content::ImportError, match: /a shift called month-end already exists in the basics track/) do
      Content::Import.new(@root).run
    end
  end

  test "Workshop targets import with their cards, linked to a Blue shift" do
    @target = workshop_target
    import!

    target = Target.find_by!(slug: "month-end-run")
    assert_equal [ "month-end", 20 ], [ target.shift.slug, target.budget ]
    assert_equal %w[ pretext pretext sender sender lure lure payload payload timing timing ], target.options.map(&:category)
    assert_equal "New bank details", target.options.first.subject
    assert_equal "Busy Bob", BotPersona.sole.name
  end

  test "rejects bad Workshop content" do
    {
      "a card in the wrong slot" => [ ->(t) { t["cards"]["sender"].first["technique"] = "pay_tech" }, /pay_tech is a pretext technique, so it can't go in the sender slot/ ],
      "an unknown shift" => [ ->(t) { t["shift"] = "nope" }, /shift "nope" isn't one of the imported shifts/ ],
      "a pretext with no subject" => [ ->(t) { t["cards"]["pretext"].first.delete("subject") }, /subject is required for pretexts/ ],
      "a subject on a lure" => [ ->(t) { t["cards"]["lure"].first["subject"] = "Hi" }, /subject is only for pretexts/ ],
      "a slot with one card" => [ ->(t) { t["cards"]["timing"].pop }, /timing needs at least 2 cards/ ],
      "a missing slot" => [ ->(t) { t["cards"].delete("payload") }, /payload must be a list/ ],
      "a budget too small for any full set" => [ ->(t) { t["budget"] = 2 }, /costs 3 together, over the budget of 2/ ],
      "a real address on a card" => [ ->(t) { t["cards"]["sender"].first["text"] = "Tidemark <accounts@tidemark.com>" }, /text mentions names outside the reserved fictional set/ ],
      "relevance out of range" => [ ->(t) { t["cards"]["pretext"].first["relevance"] = 4 }, /relevance must be from 0 to 3/ ],
      "a repeated card key" => [ ->(t) { t["cards"]["lure"].last["key"] = "link" }, /card keys must be unique \(link\)/ ]
    }.each do |description, (mutate, message)|
      @target = workshop_target
      mutate.call(@target)

      error = assert_raises(Content::ImportError, "expected an error for #{description}") { import! }
      assert_match message, error.message, "wrong error for #{description}"
    end
  end

  test "YAML aliases are refused" do
    write_content
    @root.join("tracks/basics/_track.yml").write("base: &base\n  title: x\nother: *base\n")

    assert_raises(Content::ImportError, match: /isn't valid YAML/) { Content::Import.new(@root).run }
  end

  private
    def assert_import_error(message)
      assert_raises(Content::ImportError, match: Regexp.new(Regexp.escape(message))) { import! }
    end

    def import!
      write_content
      Content::Import.new(@root).run
    end

    def write_content
      techniques = [
        { "key" => "lookalike_domain", "name" => "Lookalike domain", "attack_id" => "T1583.001", "category" => "sender",
          "description" => "A domain like the real one.", "defence_tip" => "Read domains carefully.",
          "red_cost" => 3, "stealth" => 6, "red_flag_label" => "Lookalike sender domain" }
      ]
      if @extra_techniques
        { "pay_tech" => "pretext", "link_tech" => "lure", "page_tech" => "payload", "time_tech" => "timing" }.each do |key, category|
          techniques << { "key" => key, "name" => key.humanize, "category" => category, "description" => "x", "defence_tip" => "x",
                          "red_cost" => 0, "stealth" => 5, "red_flag_label" => key.humanize }
        end
      end
      write_yaml("techniques.yml", "techniques" => techniques)
      write_yaml("badges.yml", "badges" => [
        { "key" => "first_catch", "name" => "First Catch", "description" => "Report a phish.", "side" => "blue" }
      ])
      write_yaml("tracks/basics/_track.yml", valid_track)
      write_yaml("tracks/basics/month-end.yml", @shift)
      write_yaml("bots.yml", "bots" => [
        { "key" => "busy_bob", "name" => "Busy Bob", "description" => "Always behind.", "vigilance" => 3,
          "detects" => { "lookalike_domain" => -1 } }
      ])
      write_yaml("targets/month-end-run.yml", @target) if @target
    end

    def valid_target
      card = ->(key, technique, extra = {}) { { "key" => key, "technique" => technique, "label" => key.humanize, "text" => "Text for #{key}." }.merge(extra) }
      {
        "slug" => "month-end-run", "title" => "Month-end", "shift" => "month-end", "budget" => 20,
        "recon_brief" => "Tidemark's invoice is due.",
        "cards" => {
          "pretext" => [ card.("bank", "lookalike_domain", "subject" => "New bank details"), card.("overdue", "lookalike_domain", "subject" => "Overdue") ],
          "sender" => [ card.("lookalike", "lookalike_domain"), card.("lookalike_too", "lookalike_domain") ],
          "lure" => [ card.("link", "lookalike_domain"), card.("link_too", "lookalike_domain") ],
          "payload" => [ card.("page", "lookalike_domain"), card.("page_too", "lookalike_domain") ],
          "timing" => [ card.("friday", "lookalike_domain"), card.("monday", "lookalike_domain") ]
        }
      }
    end

    def write_yaml(path, data)
      file = @root.join(path)
      file.dirname.mkpath
      file.write(data.to_yaml)
    end

    def valid_track
      { "title" => "Basics", "description" => "The basics.", "position" => 1, "difficulty" => "beginner" }
    end

    def valid_shift
      {
        "slug" => "month-end", "title" => "Month-end", "kind" => "inbox", "difficulty" => "beginner",
        "par_minutes" => 10, "briefing" => "It's month-end.", "learning_summary" => "Check links.",
        "messages" => [
          { "key" => "real_invoice", "channel" => "email", "legit" => true, "expects" => "act", "points" => 40,
            "urgent_within_minutes" => 10, "from_name" => "Tidemark",
            "from_address" => "accounts@tidemark.example", "to_address" => "you@larkhill.example",
            "subject" => "Invoice ready",
            "body_html" => %(<p><a href="https://portal.larkhill.example/invoices/4471">Review invoice</a></p>),
            "links" => [ { "match" => "portal.larkhill.example", "outcome" => "portal", "action" => "Approve invoice" } ] },
          { "key" => "canteen_news", "channel" => "email", "legit" => true, "expects" => "archive", "points" => 10,
            "from_name" => "Larkhill Canteen", "from_address" => "canteen@larkhill.example", "to_address" => "you@larkhill.example",
            "subject" => "New menu", "body_html" => "<p>Soup of the day is back.</p>" },
          { "key" => "fake_invoice", "channel" => "email", "legit" => false, "arrives" => { "after_handled" => 1 },
            "techniques" => [ "lookalike_domain" ], "from_name" => "Tidemark",
            "from_address" => "accounts@tidemark-billing.example", "to_address" => "you@larkhill.example",
            "subject" => "URGENT invoice",
            "body_html" => %(<p>Please pay today. Our bank details have changed.</p>) +
              %(<p><a href="https://larkhill-portal.example.net/login">https://portal.larkhill.example/invoices/4471</a></p>),
            "links" => [ { "match" => "larkhill-portal.example.net", "outcome" => "bait_landing" } ],
            "red_flags" => [
              { "key" => "lookalike", "anchor" => "from", "points" => 10, "label" => "Lookalike",
                "explanation" => "tidemark-billing.example is not tidemark.example." },
              { "key" => "link_mismatch", "anchor" => "l1", "points" => 10, "label" => "Mismatch",
                "explanation" => "The text and destination differ." },
              { "key" => "pay_today", "quote" => "Please pay today", "points" => 10, "label" => "Rushed",
                "explanation" => "Urgency is a tell." }
            ] }
        ],
        "hints" => [ { "body" => "Compare the domains." } ]
      }
    end

    # The canteen news sets up two facts: a later phish contradicts one, and a colleague's question is
    # answered by the other.
    def with_story(shift)
      shift["messages"][1]["body_html"] = "<p>Soup of the day is back, in Room 4B. Tidemark invoices only ever come through the portal.</p>"
      shift["messages"][2]["red_flags"].last["contradicts"] = { "message" => "canteen_news", "quote" => "Tidemark invoices only ever come through the portal" }
      shift["messages"] << newsletter.merge(
        "key" => "lunch_question", "expects" => "reply", "from_name" => "Alex Morgan", "from_address" => "alex.morgan@larkhill.example",
        "subject" => "Lunch?", "body_html" => "<p>Which room is the soup in today?</p>", "arrives" => { "after_handled" => 1 },
        "replies" => [ { "text" => "Room 4B", "outcome" => "safe" }, { "text" => "Room 2A", "outcome" => "poor" } ],
        "answer_in" => { "message" => "canteen_news", "quote" => "Room 4B" })
      shift
    end

    def newsletter
      { "key" => "newsletter", "channel" => "email", "legit" => true, "expects" => "archive", "points" => 10,
        "from_name" => "Larkhill News", "from_address" => "news@larkhill.example", "to_address" => "you@larkhill.example",
        "subject" => "This week", "body_html" => "<p>The canteen has a new menu.</p>" }
    end

    # Turns the valid shift into a messages shift, played on a phone, with chats instead of emails.
    def phone(shift)
      shift["kind"] = "messages"
      shift["messages"].each { |message| message.merge!("channel" => "chat").except!("to_address", "subject") }
      shift
    end

    def chat_replies
      [ { "text" => "Here it is: 482 913", "outcome" => "compromise", "response" => "Thanks, all sorted!" },
        { "text" => "I won't share a code.", "outcome" => "safe" },
        { "text" => "I'll check with the service desk.", "outcome" => "verify" } ]
    end

    # A valid target whose cards use one technique per slot, from a techniques file with all five.
    def workshop_target
      @extra_techniques = true
      valid_target.tap do |target|
        { "pretext" => "pay_tech", "sender" => "lookalike_domain", "lure" => "link_tech", "payload" => "page_tech", "timing" => "time_tech" }
          .each { |slot, technique| target["cards"][slot].each { |card| card["technique"] = technique } }
      end
    end

    def poor_replies
      [ { "text" => "No.", "outcome" => "poor" }, { "text" => "Go away.", "outcome" => "poor" } ]
    end

    def snapshot
      [ Technique, Badge, Track, Shift, Message, Link, RedFlag, MessageTechnique, Hint ].to_h do |model|
        [ model.name, model.order(:id).map { |record| record.attributes.except("updated_at") } ]
      end
    end

    def shipped_shift_slugs
      Rails.root.glob("content/tracks/*/*.yml").map { |file| file.basename(".yml").to_s } - [ "_track" ]
    end
end
