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
      assert_includes 4..8, shift.messages.count, "#{shift.slug} should have 4-8 messages"
      assert_includes 2..3, shift.tasks.count, "#{shift.slug} should have 2-3 tasks"
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
    fake = shift.messages.find_by!(key: "fake_invoice")
    real_link = shift.messages.find_by!(key: "real_invoice").links.sole

    assert shift.published?
    assert_equal shift.tasks.find_by!(key: "pay_supplier"), real_link.task
    assert_equal "portal_task", real_link.landing_template
    assert_equal "credential_harvest", fake.links.sole.landing_template
    assert_equal %w[ lookalike_domain ], fake.techniques.pluck(:key)
    assert_equal %w[ from l1 ], fake.red_flags.order(:id).pluck(:anchor)
    assert_includes fake.body_html, %(data-link-key="l1")
    assert_not_includes fake.body_html, "href"
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
    assert_equal %w[ lookalike ], message.red_flags.pluck(:key)
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
    @shift["messages"].last["links"].first["outcome"] = "completes_task"

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
      "a missing anchor" => [ ->(s) { s["messages"].last["red_flags"].first["anchor"] = "p9" },
                              /anchor "p9" doesn't exist in this message/ ],
      "a descriptive anchor" => [ ->(s) { s["messages"].last["red_flags"].first["anchor"] = "flag-urgency" },
                                  /anchor "flag-urgency" doesn't exist/ ],
      "reply_to anchor without a reply_to" => [ ->(s) { s["messages"].last["red_flags"].first["anchor"] = "reply_to" },
                                                /anchor "reply_to" doesn't exist/ ],
      "a task nobody can complete" => [ ->(s) { s["tasks"] << { "key" => "extra", "title" => "Extra", "due_at_minute" => 5, "points" => 5 } },
                                        /task "extra" must be completable by exactly one link in a legitimate message \(found 0\)/ ],
      "a task completed by two links" => [
        ->(s) { s["messages"].first["body_html"] += %(<p><a href="https://portal.larkhill.example/again">again</a></p>) },
        /task "pay_supplier" must be completable by exactly one link .* \(found 2\)/ ],
      "a phish that completes a task" => [ ->(s) { s["messages"].last["links"].first.merge!("outcome" => "completes_task", "task" => "pay_supplier") },
                                           /outcome must be one of bait_landing, malware, harmless for phishing messages/ ],
      "a legit message with a bait link" => [ ->(s) { s["messages"].first["links"].first.merge!("outcome" => "bait_landing").delete("task") },
                                              /outcome must be one of completes_task, harmless for legitimate messages/ ],
      "a link no rule matches" => [ ->(s) { s["messages"].first["links"].first["match"] = "nowhere.example" },
                                    /link l1 \(.*\) matches 0 link rules/ ],
      "a rule matching no link" => [ ->(s) { s["messages"].first["links"] << { "match" => "nowhere.example", "outcome" => "harmless" } },
                                     /match "nowhere.example" doesn't match any link/ ],
      "a mismatched landing" => [ ->(s) { s["messages"].last["links"].first["landing"] = "portal_task" },
                                  /landing for a bait_landing link must be credential_harvest/ ],
      "an unknown technique" => [ ->(s) { s["messages"].last["techniques"] = [ "made_up" ] }, /unknown technique "made_up"/ ],
      "a phish without techniques" => [ ->(s) { s["messages"].last.delete("techniques") }, /need at least one technique/ ],
      "a phish without red flags" => [ ->(s) { s["messages"].last.delete("red_flags") }, /need at least one red flag/ ],
      "a legit message with red flags" => [ ->(s) { s["messages"].first["red_flags"] = s["messages"].last["red_flags"].deep_dup },
                                            /legitimate messages can't have red flags/ ],
      "no phishing at all" => [ ->(s) { s["messages"].pop }, /needs at least one phishing message/ ],
      "a task due after the shift ends" => [ ->(s) { s["tasks"].first["due_at_minute"] = 31 }, /is after the shift ends/ ],
      "a message arriving after the shift ends" => [ ->(s) { s["messages"].last["arrives_at_minute"] = 30 }, /arrives_at_minute/ ],
      "a wrongly typed field" => [ ->(s) { s["time_budget_minutes"] = "thirty" }, /time_budget_minutes must be a integer/ ],
      "an unknown kind" => [ ->(s) { s["kind"] = "voice" }, /kind must be one of inbox, messages/ ],
      "an email without a subject" => [ ->(s) { s["messages"].first.delete("subject") }, /subject is required for emails/ ],
      "duplicate message keys" => [ ->(s) { s["messages"].last["key"] = "real_invoice" }, /message keys must be unique/ ],
      "a real domain on an uncommon TLD" => [ ->(s) { s["briefing"] = "Log in at realbank.co.za" },
                                              /briefing mentions names outside the reserved fictional set: realbank\.co\.za/ ],
      "a real domain in the shift title" => [ ->(s) { s["title"] = "Month-end at realbank.com" }, /title mentions names/ ],
      "a real brand in a red flag label" => [ ->(s) { s["messages"].last["red_flags"].first["label"] = "Not really PayPal" },
                                              /label mentions names outside the reserved fictional set: PayPal/ ],
      "a real brand as an SMS sender" => [ ->(s) { s["messages"].first["from_address"] = "PayPal" },
                                           /from_address "PayPal" must be a fictional address/ ],
      "a repeated technique" => [ ->(s) { s["messages"].last["techniques"] = %w[ lookalike_domain lookalike_domain ] },
                                  /messages\[1\] \(fake_invoice\): technique keys must be unique \(lookalike_domain\)/ ],
      "an unknown action cost" => [ ->(s) { s["action_costs"] = { "teleport" => 1 } }, /unknown action: teleport/ ],
      "a fake arriving after the message it imitates" => [ ->(s) { s["messages"].last["imitates"] = "pay_supplier" },
                                                          /arrives at minute 3, after the genuine message \(minute 0\)/ ],
      "a genuine message imitating a task" => [ ->(s) { s["messages"].first["imitates"] = "pay_supplier" },
                                               /only phishing messages can imitate a task/ ],
      "imitating an unknown task" => [ ->(s) { s["messages"].last.merge!("imitates" => "nope", "arrives_at_minute" => 0) },
                                      /imitates "nope", which isn't in this shift's tasks/ ]
    }.each do |description, (mutate, message)|
      @shift = valid_shift
      mutate.call(@shift)

      error = assert_raises(Content::ImportError, "expected an error for #{description}") { import! }
      assert_match message, error.message, "wrong error for #{description}"
    end
  end

  test "a fake may imitate a task if it arrives no later than the genuine message" do
    @shift["messages"].last.merge!("imitates" => "pay_supplier", "arrives_at_minute" => 0)
    assert_nothing_raised { import! }
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
        "time_budget_minutes" => 30, "briefing" => "It's month-end.", "learning_summary" => "Check links.",
        "tasks" => [ { "key" => "pay_supplier", "title" => "Approve invoice", "due_at_minute" => 20, "points" => 40 } ],
        "messages" => [
          { "key" => "real_invoice", "channel" => "email", "legit" => true, "from_name" => "Tidemark",
            "from_address" => "accounts@tidemark.example", "to_address" => "you@larkhill.example",
            "subject" => "Invoice ready",
            "body_html" => %(<p><a href="https://portal.larkhill.example/invoices/4471">Review invoice</a></p>),
            "links" => [ { "match" => "portal.larkhill.example", "outcome" => "completes_task", "task" => "pay_supplier" } ] },
          { "key" => "fake_invoice", "channel" => "email", "legit" => false, "arrives_at_minute" => 3,
            "techniques" => [ "lookalike_domain" ], "from_name" => "Tidemark",
            "from_address" => "accounts@tidemark-billing.example", "to_address" => "you@larkhill.example",
            "subject" => "URGENT invoice",
            "body_html" => %(<p><a href="https://larkhill-portal.example.net/login">https://portal.larkhill.example/invoices/4471</a></p>),
            "links" => [ { "match" => "larkhill-portal.example.net", "outcome" => "bait_landing" } ],
            "red_flags" => [
              { "key" => "lookalike", "anchor" => "from", "points" => 10, "label" => "Lookalike",
                "explanation" => "tidemark-billing.example is not tidemark.example." },
              { "key" => "link_mismatch", "anchor" => "l1", "points" => 10, "label" => "Mismatch",
                "explanation" => "The text and destination differ." }
            ] }
        ],
        "hints" => [ { "body" => "Compare the domains." } ]
      }
    end

    def snapshot
      [ Technique, Badge, Track, Shift, Task, Message, Link, RedFlag, MessageTechnique, Hint ].to_h do |model|
        [ model.name, model.order(:id).map { |record| record.attributes.except("updated_at") } ]
      end
    end

    def shipped_shift_slugs
      Rails.root.glob("content/tracks/*/*.yml").map { |file| file.basename(".yml").to_s } - [ "_track" ]
    end
end
