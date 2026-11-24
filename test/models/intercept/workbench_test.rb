require "test_helper"

class Intercept::WorkbenchTest < ActiveSupport::TestCase
  test "every step a recipe can be undone with is a Workbench operation" do
    undo = Intercept::Cipher::STEPS.values.map { |step| step[:undo] }.uniq
    assert_empty undo - Intercept::Workbench::OPERATIONS.map(&:name)
  end

  test "the JavaScript implements every operation, and nothing else" do
    source = Rails.root.join("app/javascript/workbench/operations.js").read
    exported = source[/export const OPERATIONS = \{(.*?)\n\}/m, 1].scan(/^\s+(\w+)(?:[,:]|$)/).flatten
    assert_equal Intercept::Workbench::OPERATIONS.map(&:name).sort, exported.sort
  end

  test "describes a step for the debrief" do
    assert_equal "From Base64", Intercept::Workbench.describe("from_base64", nil)
    assert_equal "ROT (shift letters): 13", Intercept::Workbench.describe("rot", 13)
    assert_raises(ArgumentError) { Intercept::Workbench.describe("magic", nil) }
  end
end
