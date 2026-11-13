require "test_helper"

# Month-end: the real invoice's portal needs your staff number; the fake invoice's lookalike page wants
# it, and the newsletter offers replies so it has a Send details box.
class ShiftAttempt::SharingTest < ActiveSupport::TestCase
  setup do
    messages(:real_invoice).update!(needs: [ "staff_number" ])
    messages(:fake_invoice).update!(wants: [ "staff_number", "mfa_code" ])
    messages(:newsletter).update!(replies: [ { "id" => "r1", "text" => "Thanks!", "outcome" => "safe" },
                                             { "id" => "r2", "text" => "Why?", "outcome" => "ask_why", "response" => "Just because." } ])
    @attempt = ShiftAttempt.start(user: users(:one), shift: shifts(:month_end))
  end

  test "chips are the persona card's details (not the MFA code until a page asks for one) and the player's notes" do
    assert_equal %w[ name role staff_number extension memorable_word security_answer ], @attempt.chips.map(&:id)
    assert_equal @attempt.persona.staff_number, @attempt.chips.find { |chip| chip.id == "staff_number" }.value

    @attempt.save_note(messages(:newsletter), "p1s1")
    assert_equal [ "Note", "The canteen has a new menu." ], @attempt.chips.last.then { |chip| [ chip.label, chip.value ] }
  end

  test "sending details from a message's box stores a copy, and the same answer comes back whatever was sent" do
    @attempt.share_details(messages(:newsletter), %w[ staff_number name ])

    result = @attempt.actions.last.result
    assert_equal [ "share_details", "reply" ], [ @attempt.actions.last.kind, result["via"] ]
    assert_equal [ [ "staff_number", "internal" ], [ "name", "public" ] ], result["shared"].map { |shared| shared.values_at("detail", "sensitivity") }
    assert_equal [ { "shared" => result["shared"], "response" => Message::DEFAULT_SHARE_RESPONSE } ], @attempt.shared_with(messages(:newsletter))
  end

  test "only real chips, at least one, and only to a message with replies" do
    assert_raises(ShiftAttempt::Rejected, match: /at least one/) { @attempt.share_details(messages(:newsletter), []) }
    assert_raises(ShiftAttempt::Rejected, match: /isn't one of your details/) { @attempt.share_details(messages(:newsletter), %w[ mfa_code ]) }
    assert_raises(ShiftAttempt::Rejected, match: /can't send details/) { @attempt.share_details(messages(:real_invoice), %w[ name ]) }
  end

  test "a portal page's fields are what its message needs, and picking a chip shares it with that message" do
    @attempt.visit(links(:real_invoice_link))
    assert_equal %w[ staff_number ], @attempt.current_tab.fields.map(&:key)

    @attempt.use_portal(details: %w[ staff_number ])

    share, press = @attempt.actions.last(2)
    assert_equal [ "share_details", "page", { "link" => "l1" } ], [ share.kind, share.result["via"], share.result["page"] ]
    assert press.use_portal?
    assert @attempt.scorecard.message_result_for("real_invoice").needs_met?
  end

  test "a page takes no more chips than it has fields" do
    @attempt.visit(links(:real_invoice_link))

    assert_raises(ShiftAttempt::Rejected, match: /only has 1 field/) { @attempt.use_portal(details: %w[ staff_number name ]) }
  end

  test "a lookalike page asks for what the phish wants, and opening one that wants the MFA code brings a code" do
    @attempt.archive(messages(:newsletter))
    assert_nil @attempt.mfa_code

    @attempt.visit(links(:fake_invoice_link))
    assert_equal %w[ staff_number mfa_code ], @attempt.current_tab.fields.map(&:key)
    assert_match(/\A\d{6}\z/, @attempt.mfa_code)
    assert_includes @attempt.chips.map(&:id), "mfa_code"

    @attempt.submit_credentials(details: %w[ mfa_code ])
    assert @attempt.scorecard.message_result_for("fake_invoice").compromised?
  end
end
