require "test_helper"

class BotPersonaTest < ActiveSupport::TestCase
  test "detection bonuses default to nothing, and must be whole numbers" do
    bob = bot_personas(:busy_bob)

    assert_equal(-2, bob.detection_bonus(:end_of_day_rush))
    assert_equal 0, bob.detection_bonus(:lookalike_domain)

    bob.detects = { "lookalike_domain" => 1.5 }
    assert_not bob.valid?
  end

  test "vigilance is 1 to 10, in the database too" do
    assert_raises(ActiveRecord::StatementInvalid) { bot_personas(:busy_bob).update_column(:vigilance, 11) }
  end
end
