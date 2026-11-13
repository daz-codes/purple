require "test_helper"

class ShiftAttempt::BrowsingTest < ActiveSupport::TestCase
  setup do
    @attempt = ShiftAttempt.start(user: users(:one), shift: shifts(:month_end))
  end

  test "visiting a link opens it in a tab, and closing the tab is logged" do
    @attempt.visit(links(:real_invoice_link))

    assert_equal messages(:real_invoice), @attempt.current_tab.message
    assert_equal({ "link" => "l1" }, @attempt.actions.last.result)

    @attempt.close_tab
    assert_nil @attempt.current_tab
    assert_equal "close_landing", @attempt.actions.last.kind
  end

  test "a new link replaces the open tab" do
    @attempt.archive(messages(:newsletter))
    @attempt.visit(links(:real_invoice_link))
    @attempt.visit(links(:fake_invoice_link))

    assert_equal messages(:fake_invoice), @attempt.current_tab.message
  end

  test "links in messages that haven't arrived or were dealt with can't be visited" do
    assert_raises(ShiftAttempt::Rejected, match: /isn't in your inbox/) { @attempt.visit(links(:fake_invoice_link)) }

    @attempt.archive(messages(:newsletter))
    @attempt.report(messages(:fake_invoice))
    assert_raises(ShiftAttempt::Rejected, match: /already dealt with/) { @attempt.visit(links(:fake_invoice_link)) }
  end

  test "attachments open in a tab" do
    @attempt.open_attachment(messages(:real_invoice), "a1")

    assert_equal "file_preview", @attempt.current_tab.landing
    assert_raises(ShiftAttempt::Rejected, match: /attachment isn't there/) { @attempt.open_attachment(messages(:real_invoice), "a9") }
  end

  test "opening the page that's already open is refused, so a double-click is logged once" do
    @attempt.visit(links(:real_invoice_link))
    assert_raises(ShiftAttempt::Rejected, match: /already open/) { @attempt.visit(links(:real_invoice_link)) }
  end

  test "dealing with a message closes its tab, so nothing more can be done on that page" do
    @attempt.archive(messages(:newsletter))
    @attempt.visit(links(:fake_invoice_link))
    @attempt.report(messages(:fake_invoice))

    assert_nil @attempt.current_tab
    assert_raises(ShiftAttempt::Rejected, match: /no sign-in page/) { @attempt.submit_credentials }
  end

  test "a tab whose link a re-import removed is gone, rather than breaking the page" do
    @attempt.visit(links(:real_invoice_link))
    links(:real_invoice_link).destroy!

    assert_nil @attempt.reload.current_tab
  end

  test "there's nothing to close when no tab is open" do
    assert_raises(ShiftAttempt::Rejected, match: /no page open/) { @attempt.close_tab }
  end
end
