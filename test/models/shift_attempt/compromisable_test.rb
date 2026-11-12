require "test_helper"

class ShiftAttempt::CompromisableTest < ActiveSupport::TestCase
  setup do
    @attempt = ShiftAttempt.start(user: users(:one), shift: shifts(:month_end))
    @attempt.wait_for_mail
  end

  test "signing in on a lookalike page compromises the player, closes the tab and the shift carries on" do
    @attempt.visit(links(:fake_invoice_link))
    @attempt.submit_credentials

    assert @attempt.compromised?
    assert_nil @attempt.current_tab
    assert @attempt.open?
    assert_equal({ "link" => "l1" }, @attempt.actions.last.result)
  end

  test "running a disguised attachment compromises the player" do
    @attempt.open_attachment(messages(:fake_invoice), "a1")
    @attempt.run_download

    assert @attempt.compromised?
  end

  test "you can only sign in on a sign-in page, or run a download from a download" do
    assert_raises(ShiftAttempt::Rejected, match: /no sign-in page/) { @attempt.submit_credentials }

    @attempt.visit(links(:real_invoice_link))
    assert_raises(ShiftAttempt::Rejected, match: /no sign-in page/) { @attempt.submit_credentials }
    assert_raises(ShiftAttempt::Rejected, match: /no download/) { @attempt.run_download }

    @attempt.open_attachment(messages(:real_invoice), "a1")
    assert_raises(ShiftAttempt::Rejected, match: /no download/) { @attempt.run_download }
    assert_not @attempt.compromised?
  end
end
