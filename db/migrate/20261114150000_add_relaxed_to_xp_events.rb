# M9: relaxed and timed play are ranked separately (see M6b), so each XP event remembers whether it came
# from a relaxed attempt.
class AddRelaxedToXpEvents < ActiveRecord::Migration[8.2]
  def change
    add_column :xp_events, :relaxed, :boolean, null: false, default: false
  end
end
