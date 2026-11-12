require "test_helper"

class TechniqueTest < ActiveSupport::TestCase
  test "links to MITRE ATT&CK" do
    assert_equal "https://attack.mitre.org/techniques/T1583/001/", techniques(:lookalike_domain).attack_url
    assert_nil techniques(:end_of_day_rush).attack_url
  end

  test "validates the ATT&CK id format and stealth range" do
    technique = techniques(:lookalike_domain)

    technique.attack_id = "lookalike"
    assert_not technique.valid?

    technique.attack_id = "T1583.001"
    technique.stealth = 11
    assert_not technique.valid?
  end

  test "can't be deleted while messages use it" do
    assert_raises(ActiveRecord::DeleteRestrictionError) { techniques(:lookalike_domain).destroy }
  end
end
