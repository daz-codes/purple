require "test_helper"

class Content::ReservedNamesTest < ActiveSupport::TestCase
  test "reserved hosts" do
    %w[ example.com mail.example.com example.net portal.example.org contoso.example a.b.test thing.invalid ].each do |host|
      assert Content::ReservedNames.reserved_host?(host), "#{host} should be reserved"
    end
  end

  test "real hosts are not reserved, including lookalikes of reserved names" do
    %w[ google.com example.co.uk notexample.com example.com.evil.net exampletest.com contoso.com ].each do |host|
      assert_not Content::ReservedNames.reserved_host?(host), "#{host} should not be reserved"
    end
  end

  test "urls must be http(s) on a reserved host" do
    assert Content::ReservedNames.reserved_url?("https://portal.contoso.example/invoices/1")
    assert_not Content::ReservedNames.reserved_url?("https://contoso.com/login")
    assert_not Content::ReservedNames.reserved_url?("javascript:alert(1)")
    assert_not Content::ReservedNames.reserved_url?("mailto:someone@contoso.example")
    assert_not Content::ReservedNames.reserved_url?("not a url")
  end

  test "addresses: reserved email, drama phone numbers or SMS sender IDs" do
    assert Content::ReservedNames.reserved_address?("accounts@northwind.example")
    assert Content::ReservedNames.reserved_address?("07700 900461")
    assert Content::ReservedNames.reserved_address?("+44 7700 900461")
    assert Content::ReservedNames.reserved_address?("NWLogistics")

    assert_not Content::ReservedNames.reserved_address?("someone@gmail.com")
    assert_not Content::ReservedNames.reserved_address?("07911 123456")
    assert_not Content::ReservedNames.reserved_address?("12345")
    assert_not Content::ReservedNames.reserved_address?("WayTooLongSenderName")
  end

  test "finds unreserved urls, emails and host names in text" do
    text = "Visit https://realbank.com/login or email help@realbank.com, or go to www.realbank.co.uk. " \
           "https://portal.contoso.example and ops@contoso.example are fine, as is Delivery_Note.pdf."

    assert_equal %w[ https://realbank.com/login help@realbank.com www.realbank.co.uk ],
      Content::ReservedNames.unreserved_names_in(text)
  end
end
