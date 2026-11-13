require "test_helper"

class ShiftAttempt::CompromisableTest < ActiveSupport::TestCase
  setup do
    @attempt = ShiftAttempt.start(user: users(:one), shift: shifts(:month_end))
    @attempt.archive(messages(:newsletter))
  end

  test "signing in on a lookalike page carries on to a plain confirmation: nothing says it went wrong" do
    @attempt.visit(links(:fake_invoice_link))
    @attempt.submit_credentials

    assert @attempt.current_tab.submitted?
    assert @attempt.open?
    assert_equal({ "link" => "l1" }, @attempt.actions.last.result)
    assert @attempt.scorecard.message_result_for("fake_invoice").compromised?
    assert_raises(ShiftAttempt::Rejected, match: /already been sent/) { @attempt.submit_credentials }
  end

  test "running a disguised attachment closes it quietly" do
    @attempt.open_attachment(messages(:fake_invoice), "a1")
    @attempt.run_download

    assert_nil @attempt.current_tab
    assert @attempt.scorecard.message_result_for("fake_invoice").compromised?
  end

  test "you can only sign in on a sign-in page, or run a download from a download" do
    assert_raises(ShiftAttempt::Rejected, match: /no sign-in page/) { @attempt.submit_credentials }

    @attempt.visit(links(:real_invoice_link))
    assert_raises(ShiftAttempt::Rejected, match: /no sign-in page/) { @attempt.submit_credentials }
    assert_raises(ShiftAttempt::Rejected, match: /no download/) { @attempt.run_download }
  end
end
