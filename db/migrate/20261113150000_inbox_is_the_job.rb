# M6b: the inbox is the job. Replaces the task list, the minute clock and per-move costs with
# messages that each expect something, arrival triggers, and real elapsed time.
#
# Attempts played under the old rules can't be scored under the new ones, so they're deleted, and so
# is the message content, which `bin/rails content:import` (or db:seed) rebuilds from content/.
# Nothing has been deployed yet (that's M10), so this only touches development and test data.
class InboxIsTheJob < ActiveRecord::Migration[8.2]
  ACTION_KINDS = %w[
    open_message expand_headers verify_sender click_link close_landing submit_credentials open_attachment
    run_download use_portal report_message archive_message flag_element send_reply use_hint give_up
  ].freeze

  def up
    safety_assured do
      execute "DELETE FROM attempt_actions"
      execute "DELETE FROM shift_attempts"
      execute "DELETE FROM links"
      execute "DELETE FROM red_flags"
      execute "DELETE FROM message_techniques"
      execute "DELETE FROM messages"

      # --- Shifts: a target time instead of a day length and per-move costs -------------
      remove_check_constraint :shifts, name: "shifts_time_budget_positive"
      remove_column :shifts, :time_budget_minutes
      remove_column :shifts, :action_costs
      add_column :shifts, :par_minutes, :integer, null: false, default: 10
      add_check_constraint :shifts, "par_minutes > 0", name: "shifts_par_minutes_positive"

      # --- Tasks go: each message carries what it expects ----------------------------------
      remove_check_constraint :links, name: "links_task_only_when_completing"
      remove_reference :links, :task, foreign_key: true, index: true
      drop_table :tasks

      remove_check_constraint :links, name: "links_outcome"
      remove_check_constraint :links, name: "links_landing_template"
      add_column :links, :portal_action, :string
      add_check_constraint :links, "outcome IN ('portal', 'harmless', 'bait_landing', 'malware')", name: "links_outcome"
      add_check_constraint :links, "landing_template IN ('portal', 'harmless', 'credential_harvest', 'malware_download')",
        name: "links_landing_template"
      add_check_constraint :links, "(outcome = 'portal') = (portal_action IS NOT NULL)", name: "links_portal_action_only_on_portals"

      remove_check_constraint :messages, name: "messages_arrives_at_minute_non_negative"
      remove_column :messages, :arrives_at_minute
      add_column :messages, :arrives_after_handled, :integer
      add_column :messages, :arrives_after, :string
      add_column :messages, :expects, :string
      add_column :messages, :points, :integer, null: false, default: 0
      add_column :messages, :urgent_within_minutes, :integer
      add_check_constraint :messages, "arrives_after_handled IS NULL OR arrives_after IS NULL", name: "messages_one_arrival_trigger"
      add_check_constraint :messages, "arrives_after_handled > 0", name: "messages_arrives_after_handled_positive"
      add_check_constraint :messages, "expects IN ('reply', 'act', 'archive')", name: "messages_expects"
      add_check_constraint :messages, "legit = (expects IS NOT NULL)", name: "messages_expects_only_when_genuine"
      add_check_constraint :messages, "CASE WHEN legit THEN points > 0 ELSE points = 0 END", name: "messages_points_only_when_genuine"
      add_check_constraint :messages, "urgent_within_minutes IS NULL OR (legit AND urgent_within_minutes > 0)",
        name: "messages_urgent_only_when_genuine"

      # --- Red flags in the body are quoted phrases ---------------------------------------
      add_column :red_flags, :quote, :string
      add_column :red_flags, :quote_start, :integer
      add_column :red_flags, :quote_end, :integer
      add_check_constraint :red_flags,
        "(quote IS NULL AND quote_start IS NULL AND quote_end IS NULL) OR " \
        "(quote IS NOT NULL AND quote_start >= 0 AND quote_end > quote_start)",
        name: "red_flags_quote_complete"

      # --- Attempts: real time, plus penalties ---------------------------------------------
      %w[ shift_attempts_clock_within_budget shift_attempts_clock_non_negative shift_attempts_time_budget_positive
          shift_attempts_status ].each { |name| remove_check_constraint :shift_attempts, name: }
      remove_column :shift_attempts, :clock_minutes
      remove_column :shift_attempts, :time_budget_minutes
      remove_column :shift_attempts, :productivity_score
      remove_column :shift_attempts, :security_score
      add_column :shift_attempts, :penalty_seconds, :integer, null: false, default: 0
      add_column :shift_attempts, :relaxed, :boolean, null: false, default: false
      add_check_constraint :shift_attempts, "penalty_seconds >= 0", name: "shift_attempts_penalty_seconds_non_negative"
      add_check_constraint :shift_attempts, "status IN ('open', 'completed', 'gave_up', 'timed_out')", name: "shift_attempts_status"

      remove_check_constraint :attempt_actions, name: "attempt_actions_kind"
      remove_check_constraint :attempt_actions, name: "attempt_actions_minute_non_negative"
      remove_check_constraint :attempt_actions, name: "attempt_actions_cost_non_negative"
      remove_column :attempt_actions, :minute
      remove_column :attempt_actions, :cost_minutes
      add_column :attempt_actions, :at_seconds, :integer, null: false, default: 0
      add_column :attempt_actions, :penalty_seconds, :integer, null: false, default: 0
      add_check_constraint :attempt_actions, "kind IN (#{ACTION_KINDS.map { |kind| "'#{kind}'" }.join(", ")})", name: "attempt_actions_kind"
      add_check_constraint :attempt_actions, "at_seconds >= 0", name: "attempt_actions_at_seconds_non_negative"
      add_check_constraint :attempt_actions, "penalty_seconds >= 0", name: "attempt_actions_penalty_seconds_non_negative"

      # --- Relaxed mode: no timing at all --------------------------------------------------
      add_column :users, :relaxed_mode, :boolean, null: false, default: false
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "M6b replaced the task and clock model; restore from a backup instead"
  end
end
