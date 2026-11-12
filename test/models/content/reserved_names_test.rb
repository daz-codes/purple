require "test_helper"

class Content::ReservedNamesTest < ActiveSupport::TestCase
  test "reserved hosts" do
    %w[ example.com mail.example.com example.net portal.example.org larkhill.example a.b.test thing.invalid ].each do |host|
      assert Content::ReservedNames.reserved_host?(host), "#{host} should be reserved"
    end
  end

  test "real hosts are not reserved, including lookalikes of reserved names" do
    %w[ google.com example.co.uk notexample.com example.com.evil.net exampletest.com larkhill.com ].each do |host|
      assert_not Content::ReservedNames.reserved_host?(host), "#{host} should not be reserved"
    end
  end

  test "urls must be http(s) on a reserved host" do
    assert Content::ReservedNames.reserved_url?("https://portal.larkhill.example/invoices/1")
    assert_not Content::ReservedNames.reserved_url?("https://larkhill.com/login")
    assert_not Content::ReservedNames.reserved_url?("javascript:alert(1)")
    assert_not Content::ReservedNames.reserved_url?("mailto:someone@larkhill.example")
    assert_not Content::ReservedNames.reserved_url?("not a url")
  end

  test "addresses: reserved email, drama phone numbers or SMS sender IDs" do
    assert Content::ReservedNames.reserved_address?("accounts@tidemark.example")
    assert Content::ReservedNames.reserved_address?("07700 900461")
    assert Content::ReservedNames.reserved_address?("+44 7700 900461")
    assert Content::ReservedNames.reserved_address?("NWLogistics")

    assert_not Content::ReservedNames.reserved_address?("someone@gmail.com")
    assert_not Content::ReservedNames.reserved_address?("07911 123456")
    assert_not Content::ReservedNames.reserved_address?("12345")
    assert_not Content::ReservedNames.reserved_address?("WayTooLongSenderName")
  end

  test "SMS sender IDs can't be real brands" do
    %w[ PayPal HMRC paypal UPS ].each do |sender|
      assert_not Content::ReservedNames.reserved_address?(sender), "#{sender} should be rejected"
    end
  end

  test "finds unreserved urls, emails and host names in text" do
    text = "Visit https://realbank.com/login or email help@realbank.com, or go to www.realbank.co.uk. " \
           "https://portal.larkhill.example and ops@larkhill.example are fine, as is Delivery_Note.pdf."

    assert_equal %w[ https://realbank.com/login help@realbank.com www.realbank.co.uk ],
      Content::ReservedNames.unreserved_names_in(text)
  end

  test "host names on any top-level domain are caught, not just common ones" do
    assert_equal %w[ realbank.co.za evilbank.bank evil.tv secure.login.ch ],
      Content::ReservedNames.unreserved_names_in("Try realbank.co.za, evilbank.bank, evil.tv or secure.login.ch.")
  end

  test "file names are not host names, unless the extension is also a top-level domain" do
    assert_empty Content::ReservedNames.unreserved_names_in("Open Invoice_4471.pdf.exe or Report.docx")
    assert_equal %w[ payroll.zip ], Content::ReservedNames.unreserved_names_in("Open payroll.zip")
  end

  test "finds real brands, matching ordinary words only in their brand case" do
    assert_equal %w[ PayPal paypal UPS Zoom ],
      Content::ReservedNames.unreserved_names_in("PayPal, paypal, UPS and Zoom; ups and downs, zoom in")
  end
end
