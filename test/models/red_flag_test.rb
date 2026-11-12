require "test_helper"

class RedFlagTest < ActiveSupport::TestCase
  test "anchors must be neutral ids" do
    flag = red_flags(:lookalike)

    %w[ from reply_to to subject p1 l12 a3 ].each do |anchor|
      flag.anchor = anchor
      assert flag.valid?, "#{anchor} should be allowed"
    end

    %w[ flag-urgency p sender bank_change ].each do |anchor|
      flag.anchor = anchor
      assert_not flag.valid?, "#{anchor} should be rejected"
    end
  end
end
