require "test_helper"

class InterceptTest < ActiveSupport::TestCase
  test "normalises answers: NFKC, case folded, spaces collapsed, punctuation at the ends dropped" do
    assert_equal "fuel depot", Intercept.normalise("  Fuel   Depot. ")
    assert_equal "fuel depot", Intercept.normalise("“ＦＵＥＬ\tdepot”!")
    assert_equal "4.625 mhz", Intercept.normalise("4.625 MHz.")
    assert_equal "", Intercept.normalise(" ... ")
  end

  test "a flag matches any accepted form, and nothing else" do
    intercept = intercepts(:wrapped)
    assert intercept.flag?("old lighthouse")
    assert intercept.flag?("  The Old Lighthouse! ")
    assert_not intercept.flag?("Old Lighthouse at 0340")
    assert_not intercept.flag?("")
    assert_not intercept.flag?("...")
  end

  test "flags are kept only as keyed digests" do
    intercept = intercepts(:opening)
    assert_not_includes intercept.flag_digests.to_json, "biscuit"
    assert_not_equal Digest::SHA256.hexdigest("biscuit tin"), intercept.flag_digests.first
  end

  test "holds a body or a file, never both or neither" do
    intercept = intercepts(:opening)
    intercept.file_data = "x"
    intercept.file_name = "a.png"
    intercept.file_type = "image/png"
    assert_not intercept.valid?

    intercept.body = nil
    assert intercept.valid?
    intercept.file_data = intercept.file_name = intercept.file_type = nil
    assert_not intercept.valid?
  end

  test "lists the Workbench steps that decode it" do
    assert_equal [ [ "from_base64", nil ], [ "from_base64", nil ] ], intercepts(:wrapped).undo_steps
  end
end
