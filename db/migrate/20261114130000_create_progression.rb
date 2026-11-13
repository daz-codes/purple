# M8: progression. Each side has its own XP and level; XP comes from an append-only ledger of events.
# Daily streaks count calendar days (Europe/London) with at least one scored completion.
class CreateProgression < ActiveRecord::Migration[8.2]
  def change
    add_column :users, :preferred_side, :string
    add_column :users, :blue_xp, :integer, null: false, default: 0
    add_column :users, :red_xp, :integer, null: false, default: 0
    add_column :users, :blue_level, :integer, null: false, default: 1
    add_column :users, :red_level, :integer, null: false, default: 1
    add_column :users, :xp_total, :integer, null: false, default: 0
    add_column :users, :current_streak, :integer, null: false, default: 0
    add_column :users, :longest_streak, :integer, null: false, default: 0
    add_column :users, :last_played_on, :date
    add_column :users, :leaderboard_opt_out, :boolean, null: false, default: false

    add_check_constraint :users, "preferred_side IN ('blue', 'red')", name: "users_preferred_side", validate: false
    add_check_constraint :users, "xp_total = blue_xp + red_xp", name: "users_xp_total_is_the_sum", validate: false
    add_check_constraint :users, "blue_xp >= 0 AND red_xp >= 0", name: "users_xp_non_negative", validate: false
    add_check_constraint :users, "blue_level >= 1 AND red_level >= 1", name: "users_levels_positive", validate: false
    add_check_constraint :users, "current_streak >= 0 AND longest_streak >= current_streak", name: "users_streaks", validate: false

    create_table :xp_events do |t|
      t.references :user, null: false, foreign_key: true
      t.string :side, null: false
      t.integer :amount, null: false
      t.string :reason, null: false
      t.references :source, polymorphic: true
      t.datetime :occurred_at, null: false
      t.timestamps
      t.index %i[ user_id occurred_at ]
      t.index %i[ side occurred_at ]
      t.index %i[ user_id reason source_type source_id ], unique: true, name: "index_xp_events_once_per_source"
      t.check_constraint "side IN ('blue', 'red')", name: "xp_events_side"
      t.check_constraint "reason IN ('shift_completed', 'workshop_completed', 'streak_bonus', 'badge_awarded')", name: "xp_events_reason"
      t.check_constraint "amount >= 0", name: "xp_events_amount_non_negative"
    end
  end
end
