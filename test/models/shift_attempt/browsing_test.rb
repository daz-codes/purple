require "test_helper"

class ShiftAttempt::BrowsingTest < ActiveSupport::TestCase
  setup do
    @attempt = ShiftAttempt.start(user: users(:one), shift: shifts(:month_end))
  end

  test "visiting a link opens it in a tab for free, and closing the tab is logged" do
    @attempt.visit(links(:real_invoice_link))

    assert_equal 0, @attempt.clock_minutes
    assert_equal messages(:real_invoice), @attempt.current_tab.message
    assert_equal({ "link" => "l1" }, @attempt.actions.last.result)

    @attempt.close_tab
    assert_nil @attempt.current_tab
    assert_equal "close_landing", @attempt.actions.last.kind
  end

  test "a new link replaces the open tab" do
    @attempt.wait_for_mail
    @attempt.visit(links(:real_invoice_link))
    @attempt.visit(links(:fake_invoice_link))

    assert_equal messages(:fake_invoice), @attempt.current_tab.message
  end

  test "links in messages that haven't arrived or were reported can't be visited" do
    assert_raises(ShiftAttempt::Rejected, match: /isn't in your inbox/) { @attempt.visit(links(:fake_invoice_link)) }

    @attempt.wait_for_mail
    @attempt.report(messages(:fake_invoice))
    assert_raises(ShiftAttempt::Rejected, match: /already reported/) { @attempt.visit(links(:fake_invoice_link)) }
  end

  test "attachments open in a tab" do
    @attempt.open_attachment(messages(:real_invoice), "a1")

    assert_equal "file_preview", @attempt.current_tab.landing
    assert_raises(ShiftAttempt::Rejected, match: /attachment isn't there/) { @attempt.open_attachment(messages(:real_invoice), "a9") }
  end

  test "there's nothing to close when no tab is open" do
    assert_raises(ShiftAttempt::Rejected, match: /no page open/) { @attempt.close_tab }
  end
end
