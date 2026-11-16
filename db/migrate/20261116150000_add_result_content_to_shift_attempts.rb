class AddResultContentToShiftAttempts < ActiveRecord::Migration[8.2]
  def change
    add_column :shift_attempts, :result_content, :jsonb, default: {}, null: false
  end
end
