# A player's run through a shift, and the append-only log of everything they did in it.
# The log drives the clock, the scoring and (from M5) the Purple debrief.
class CreateShiftAttempts < ActiveRecord::Migration[8.2]
  ACTION_KINDS = %w[
    open_message expand_headers verify_sender hover_link click_link close_landing submit_credentials
    open_attachment report_message flag_element complete_task use_hint wait end_shift
  ].freeze

  def change
    create_table :shift_attempts do |t|
      t.references :user, null: false, foreign_key: true
      t.references :shift, null: false, foreign_key: true
      t.string :token, null: false
      t.string :status, null: false, default: "open"
      t.integer :clock_minutes, null: false, default: 0
      # Copied from the shift at the start, so re-imported content can't move the end of the day.
      t.integer :time_budget_minutes, null: false
      # Scores stay NULL until the shift ends, so nothing about them can leak mid-shift.
      t.integer :productivity_score
      t.integer :security_score
      t.integer :score
      t.integer :hints_used, null: false, default: 0
      t.datetime :started_at, null: false
      t.datetime :completed_at
      t.boolean :scored, null: false, default: false
      t.timestamps

      t.index :token, unique: true
      # Only the first finished attempt per shift earns XP.
      t.index %i[ user_id shift_id ], unique: true, where: "scored", name: "index_shift_attempts_one_scored_per_shift"
      # At most one shift in progress per player and shift: starting again resumes it.
      t.index %i[ user_id shift_id ], unique: true, where: "status = 'open'", name: "index_shift_attempts_one_open_per_shift"
      t.check_constraint "status IN ('open', 'completed', 'timed_out')", name: "shift_attempts_status"
      t.check_constraint "clock_minutes >= 0", name: "shift_attempts_clock_non_negative"
      t.check_constraint "time_budget_minutes > 0", name: "shift_attempts_time_budget_positive"
      t.check_constraint "clock_minutes <= time_budget_minutes", name: "shift_attempts_clock_within_budget"
      t.check_constraint "hints_used >= 0", name: "shift_attempts_hints_used_non_negative"
      t.check_constraint "(status = 'open') = (completed_at IS NULL)", name: "shift_attempts_completed_at_when_finished"
      t.check_constraint "(status = 'open') = (score IS NULL)", name: "shift_attempts_score_when_finished"
      t.check_constraint "NOT scored OR status <> 'open'", name: "shift_attempts_scored_only_when_finished"
    end

    create_table :attempt_actions do |t|
      # No single-column index: the [shift_attempt_id, id] index below covers lookups by attempt.
      t.references :shift_attempt, null: false, foreign_key: true, index: false
      t.string :kind, null: false
      t.string :target_key
      t.integer :minute, null: false
      t.integer :cost_minutes, null: false, default: 0
      t.jsonb :result, null: false, default: {}
      t.datetime :created_at, null: false

      t.index %i[ shift_attempt_id id ]
      t.check_constraint "kind IN (#{ACTION_KINDS.map { |kind| "'#{kind}'" }.join(", ")})", name: "attempt_actions_kind"
      t.check_constraint "minute >= 0", name: "attempt_actions_minute_non_negative"
      t.check_constraint "cost_minutes >= 0", name: "attempt_actions_cost_non_negative"
    end
  end
end
