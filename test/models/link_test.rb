require "test_helper"

class LinkTest < ActiveSupport::TestCase
  test "a portal link needs a button to press, and only portal links may have one" do
    portal = links(:real_invoice_link)
    portal.portal_action = nil
    assert_not portal.valid?

    bait = links(:fake_invoice_link)
    bait.portal_action = "Sign in"
    assert_not bait.valid?
  end

  test "the database enforces the portal rule too" do
    assert_raises(ActiveRecord::StatementInvalid) { links(:fake_invoice_link).update_column(:portal_action, "Sign in") }
  end

  test "rejects unknown landing templates" do
    link = links(:fake_invoice_link)
    link.landing_template = "real_bank_login"
    assert_not link.valid?
  end
end
