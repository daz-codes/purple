require "test_helper"

class MessageTest < ActiveSupport::TestCase
  test "phish? is the opposite of legit" do
    assert messages(:fake_invoice).phish?
    assert_not messages(:real_invoice).phish?
  end

  test "keys are unique within a shift" do
    duplicate = messages(:real_invoice).dup
    assert_not duplicate.valid?
  end

  test "a genuine message expects something and a phish doesn't, in the database too" do
    assert_not messages(:real_invoice).tap { |message| message.expects = nil }.valid?
    assert_not messages(:fake_invoice).tap { |message| message.expects = "archive" }.valid?
    assert_raises(ActiveRecord::StatementInvalid) { messages(:fake_invoice).update_column(:points, 10) }
  end

  test "destroying a message removes its links, red flags and technique tags" do
    message = messages(:fake_invoice)

    assert_difference -> { Link.count } => -1, -> { RedFlag.count } => -2, -> { MessageTechnique.count } => -1 do
      message.destroy
    end
  end

  test "whole parts the player can flag: the headers, links and attachments; a phone message shows only its sender" do
    assert_equal %w[ from to reply_to subject l1 a1 ], messages(:fake_invoice).whole_anchors
    assert_equal %w[ from to subject l1 a1 ], messages(:real_invoice).whole_anchors
    assert_equal %w[ from ], messages(:it_chat).whole_anchors
  end

  test "paragraphs: each text block, its text as the player sees it, and its sentences" do
    paragraphs = messages(:fake_invoice).paragraphs

    assert_equal %w[ p1 p2 ], paragraphs.keys
    assert_equal "Please pay today. Our bank details have changed.", paragraphs["p1"].text
    assert_equal [ [ "p1s1", "Please pay today." ], [ "p1s2", "Our bank details have changed." ] ],
      paragraphs["p1"].sentences.map { |sentence| [ sentence.anchor, paragraphs["p1"].text[sentence.from...sentence.to] ] }
    assert_equal paragraphs["p1"], messages(:fake_invoice).paragraph_for("p1s2")
  end

  test "arrival: at the start, after a number dealt with, or after another message" do
    assert messages(:real_invoice).arrives_at_start?
    assert_not messages(:fake_invoice).arrives_at_start?
    assert_raises(ActiveRecord::StatementInvalid) { messages(:fake_invoice).update_column(:arrives_after, "real_invoice") }
  end
end
