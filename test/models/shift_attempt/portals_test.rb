require "test_helper"

class ShiftAttempt::PortalsTest < ActiveSupport::TestCase
  setup do
    @attempt = ShiftAttempt.start(user: users(:one), shift: shifts(:month_end))
  end

  test "pressing the button on a portal page does what the message asked, and the page says only that it was sent" do
    @attempt.visit(links(:real_invoice_link))
    assert_equal "Approve invoice", @attempt.current_tab.portal_action

    @attempt.use_portal

    assert @attempt.used_portal?(messages(:real_invoice))
    assert @attempt.current_tab.submitted?
    assert_raises(ShiftAttempt::Rejected, match: /already been sent/) { @attempt.use_portal }
  end

  test "there's only something to do on a portal page" do
    assert_raises(ShiftAttempt::Rejected, match: /nothing to do/) { @attempt.use_portal }

    @attempt.open_attachment(messages(:real_invoice), "a1")
    assert_raises(ShiftAttempt::Rejected, match: /nothing to do/) { @attempt.use_portal }
  end
end
