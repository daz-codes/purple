require "test_helper"

class LinkTest < ActiveSupport::TestCase
  test "a task-completing link needs a task, and only those links may have one" do
    link = links(:real_invoice_link)
    link.task = nil
    assert_not link.valid?

    bait = links(:fake_invoice_link)
    bait.task = tasks(:pay_supplier)
    assert_not bait.valid?
  end

  test "the database enforces the task rule too" do
    assert_raises(ActiveRecord::StatementInvalid) do
      links(:fake_invoice_link).update_column(:task_id, tasks(:pay_supplier).id)
    end
  end

  test "rejects unknown landing templates" do
    link = links(:fake_invoice_link)
    link.landing_template = "real_bank_login"
    assert_not link.valid?
  end
end
