# The number of hints is read from the action log (ShiftAttempt::Hintable#hints_used), so a counter
# column could only ever drift from it.
class RemoveHintsUsedFromShiftAttempts < ActiveRecord::Migration[8.2]
  def change
    safety_assured do
      remove_check_constraint :shift_attempts, "hints_used >= 0", name: "shift_attempts_hints_used_non_negative"
      remove_column :shift_attempts, :hints_used, :integer, default: 0, null: false
    end
  end
end
