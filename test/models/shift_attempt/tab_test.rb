require "test_helper"

class ShiftAttempt::TabTest < ActiveSupport::TestCase
  test "a link tab shows the link's real address and the page its landing names" do
    tab = ShiftAttempt::Tab.new(message: messages(:fake_invoice), source: { "link" => "l1" })

    assert_equal "credential_harvest", tab.landing
    assert_equal "https://contoso-portal.example.net/login", tab.address
    assert_equal "contoso-portal.example.net", tab.title
    assert tab.padlock?, "https phishing sites have padlocks too"
    assert_nil tab.task
  end

  test "a portal tab knows the task it completes" do
    tab = ShiftAttempt::Tab.new(message: messages(:real_invoice), source: { "link" => "l1" })

    assert_equal "portal_task", tab.landing
    assert_equal tasks(:pay_supplier), tab.task
  end

  test "attachments preview documents and prompt before running programs" do
    document = ShiftAttempt::Tab.new(message: messages(:real_invoice), source: { "attachment" => "a1" })
    program = ShiftAttempt::Tab.new(message: messages(:fake_invoice), source: { "attachment" => "a1" })

    assert_equal [ "file_preview", "Invoice_4471.pdf", nil ], [ document.landing, document.file_name, document.address ]
    assert_equal [ "malware_download", "Remittance_4471.pdf.exe" ], [ program.landing, program.file_name ]
  end

  test "a download link offers the file named in its URL" do
    links(:fake_invoice_link).update!(actual_url: "https://files.example.net/Invoice_4471.zip", outcome: "malware",
                                      landing_template: "malware_download")
    tab = ShiftAttempt::Tab.new(message: messages(:fake_invoice).reload, source: { "link" => "l1" })

    assert_equal "Invoice_4471.zip", tab.file_name
  end
end
