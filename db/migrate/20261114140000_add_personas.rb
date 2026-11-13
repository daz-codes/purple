# M7b: who the player is. A shift sets the persona's name, role and staff-number prefix, its security
# question and the staff directory; each attempt stores the details generated for it, so a later change
# to the word lists can't rewrite an old debrief.
class AddPersonas < ActiveRecord::Migration[8.2]
  def change
    add_column :shifts, :persona, :jsonb, null: false, default: {}
    add_column :shifts, :directory, :jsonb, null: false, default: []
    add_column :shift_attempts, :persona_details, :jsonb, null: false, default: {}
  end
end
