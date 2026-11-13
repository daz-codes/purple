require "test_helper"

class RedFlagTest < ActiveSupport::TestCase
  test "a whole-part red flag's anchor is a neutral header, link or attachment id" do
    flag = red_flags(:lookalike)

    %w[ from reply_to to subject l12 a3 ].each do |anchor|
      flag.anchor = anchor
      assert flag.valid?, "#{anchor} should be allowed"
    end

    %w[ p1 flag-urgency p sender bank_change ].each do |anchor|
      flag.anchor = anchor
      assert_not flag.valid?, "#{anchor} should be rejected"
    end
  end

  test "a quoted red flag sits in a paragraph" do
    flag = red_flags(:pay_today)
    assert flag.valid?

    flag.anchor = "from"
    assert_not flag.valid?
  end

  test "a whole part is found by flagging that part" do
    assert red_flags(:lookalike).found_by?(flag("from"))
    assert_not red_flags(:lookalike).found_by?(flag("subject"))
    assert_not red_flags(:lookalike).found_by?(flag("p1", 0, 16))
  end

  test "a quote is found by a highlight covering most of it, or by the sentence it's in" do
    quote = red_flags(:pay_today) # "Please pay today" is 0...16 of "Please pay today. Our bank details have changed."

    assert quote.found_by?(flag("p1", 0, 16))
    assert quote.found_by?(flag("p1", 7, 16)), "\"pay today\" covers 9 of 16 characters"
    assert quote.found_by?(flag("p1", 0, 17)), "the sentence"
    assert_not quote.found_by?(flag("p1", 11, 16)), "\"today\" alone is too little"
    assert_not quote.found_by?(flag("p1", 18, 48)), "the wrong sentence"
    assert_not quote.found_by?(flag("p2", 0, 7))
    assert_not quote.found_by?(flag("from"))
  end

  test "highlighting far more than the quote, across sentences, doesn't count" do
    message = Message.new(body_html: Content::MessageBody.new(
      "<p>Hello there, I hope you are well today. Please pay today. Our bank details have changed this month.</p>").html)
    text = message.paragraphs["p1"].text
    start = text.index("Please pay today")
    quote = RedFlag.new(message:, anchor: "p1", quote: "Please pay today", quote_start: start, quote_end: start + 16)

    assert quote.found_by?(flag("p1", start, start + 17)), "its sentence"
    assert quote.found_by?(flag("p1", start - 10, start + 26)), "a little either side"
    assert_not quote.found_by?(flag("p1", 0, text.length)), "the whole paragraph"
  end

  private
    def flag(anchor, from = nil, to = nil)
      ShiftAttempt::Flag.new(anchor:, from:, to:)
    end
end
