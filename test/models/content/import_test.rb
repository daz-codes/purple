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
      assert_includes 5..9, messages.size, "#{shift.slug} should have 5-9 messages"
      assert messages.any? { |message| message.expects_reply? || message.expects_act? }, "#{shift.slug} needs a genuine message to reply to or act on"
      assert messages.any?(&:arrives_after), "#{shift.slug} needs a follow-up"
      assert messages.any? { |message| message.red_flags.any?(&:quote?) }, "#{shift.slug} needs a quoted red flag"
    end
    assert_equal 3, Shift.where(slug: shipped_shift_slugs).kind_inbox.count
    assert_equal 1, Shift.where(slug: shipped_shift_slugs).kind_messages.count
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

  test "arrivals: after a count, or after another message" do
    @shift["messages"] << newsletter.merge("arrives" => { "after" => "real_invoice" })
    import!

    assert_equal "real_invoice", Message.find_by!(key: "newsletter").arrives_after
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
    assert_match %r{\Acontent[\w-]*/tracks/basics/month-end\.yml: messages\[1\] \(fake_invoice\) → links\[0\]: }, error.message
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
      "a count the shift never reaches" => [ ->(s) { s["messages"].last["arrives"] = { "after_handled" => 2 } },
                                             /fake_invoice can never arrive/ ],
      "nothing at the start" => [ ->(s) { s["messages"].first["arrives"] = { "after" => "fake_invoice" } },
                                  /at least one message must arrive at the start/ ],
      "a loop" => [ ->(s) { s["messages"].first["arrives"] = { "after" => "fake_invoice" }; s["messages"].last["arrives"] = { "after" => "real_invoice" }; s["messages"] << newsletter },
                    /real_invoice, fake_invoice can never arrive/ ],
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
                                  /messages\[1\] \(fake_invoice\): technique keys must be unique \(lookalike_domain\)/ ],
      "an attachment on a text" => [ ->(s) { phone(s)["messages"].last["attachments"] = [ { "name" => "a.pdf", "type" => "application/pdf", "size" => "1 KB", "outcome" => "harmless" } ] },
                                     /attachments are only for emails/ ],
      "a single reply" => [ ->(s) { phone(s)["messages"].last["replies"] = chat_replies.first(1) }, /from 2 to 4 options/ ],
      "five replies" => [ ->(s) { phone(s)["messages"].last["replies"] = 5.times.map { |i| { "text" => "Reply #{i}", "outcome" => "safe" } } },
                          /from 2 to 4 options/ ],
      "a reply that hands over on a genuine message" => [
        ->(s) { phone(s)["messages"].first["replies"] = chat_replies },
        /outcome must be one of safe, poor, verify for legitimate messages \(got compromise\)/ ],
      "a poor reply on a phish" => [ ->(s) { phone(s)["messages"].last["replies"] = poor_replies },
                                     /outcome must be one of safe, compromise, verify for phishing messages \(got poor\)/ ],
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
    assert_equal 2, import!.messages
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

  test "YAML aliases are refused" do
    write_content
    @root.join("tracks/basics/_track.yml").write("base: &base\n  title: x\nother: *base\n")

    assert_raises(Content::ImportError, match: /isn't valid YAML/) { Content::Import.new(@root).run }
  end

  private
    def import!
      write_content
      Content::Import.new(@root).run
    end

    def write_content
      write_yaml("techniques.yml", "techniques" => [
        { "key" => "lookalike_domain", "name" => "Lookalike domain", "attack_id" => "T1583.001", "category" => "sender",
          "description" => "A domain like the real one.", "defence_tip" => "Read domains carefully.",
          "red_cost" => 3, "stealth" => 6, "red_flag_label" => "Lookalike sender domain" }
      ])
      write_yaml("badges.yml", "badges" => [
        { "key" => "first_catch", "name" => "First Catch", "description" => "Report a phish.", "side" => "blue" }
      ])
      write_yaml("tracks/basics/_track.yml", valid_track)
      write_yaml("tracks/basics/month-end.yml", @shift)
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
