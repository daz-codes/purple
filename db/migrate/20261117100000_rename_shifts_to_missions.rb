# Phase 2 (P0) retires the word "shift": every playable challenge is a mission, and "Clock off early"
# becomes "Stand down". This renames the tables, columns, indexes and constraints, and rewrites the
# stored values that spell the old words: attempt statuses, action kinds, XP reasons and source
# types, the Clean Shift badge's key, and the mission ids inside finished attempts' content snapshots.
#
# safety_assured: renaming tables and columns breaks code still running the old names, which
# strong_migrations rightly flags. Here it's deliberate: it ships before Purple's first production
# deploy, so no live data or players are affected, and the rename is cheapest now. (Once production
# is live, beware: bin/docker-entrypoint migrates as the new container boots, while the old one is
# still serving, so old code would briefly hit the renamed tables.) Everything runs in one transaction.
class RenameShiftsToMissions < ActiveRecord::Migration[8.2]
  ACTION_KINDS = %w[ open_message expand_headers verify_sender click_link close_landing submit_credentials
                     open_attachment run_download use_portal report_message archive_message flag_element
                     send_reply use_hint %s save_note share_details ask_why ].freeze
  STATUSES = %w[ open completed %s timed_out ].freeze
  XP_REASONS = %w[ %s workshop_completed streak_bonus badge_awarded ].freeze

  RENAMED_CONSTRAINTS = {
    mission_attempts: %w[ completed_at_when_finished score_when_finished scored_only_when_finished
                          penalty_seconds_non_negative ],
    missions: %w[ author_side author_type difficulty kind par_minutes_positive ]
  }.freeze

  def up
    safety_assured do
      rename_everything from: "shift", to: "mission"
      rewrite_values status: %w[ clocked_off stood_down ], kind: %w[ clock_off stand_down ],
                     reason: %w[ shift_completed mission_completed ]
      execute "UPDATE xp_events SET source_type = 'MissionAttempt' WHERE source_type = 'ShiftAttempt'"
      execute "UPDATE badges SET key = 'clean_mission' WHERE key = 'clean_shift'"
      rewrite_snapshots "shift_id", "mission_id"
    end
  end

  def down
    safety_assured do
      rewrite_snapshots "mission_id", "shift_id"
      execute "UPDATE badges SET key = 'clean_shift' WHERE key = 'clean_mission'"
      execute "UPDATE xp_events SET source_type = 'ShiftAttempt' WHERE source_type = 'MissionAttempt'"
      rewrite_values status: %w[ stood_down clocked_off ], kind: %w[ stand_down clock_off ],
                     reason: %w[ mission_completed shift_completed ]
      rename_everything from: "mission", to: "shift"
    end
  end

  private
    def rename_everything(from:, to:)
      rename_table :"#{from}s", :"#{to}s"
      rename_table :"#{from}_attempts", :"#{to}_attempts"

      %i[ hints messages targets ].each { |table| rename_column table, :"#{from}_id", :"#{to}_id" }
      rename_column :"#{to}_attempts", :"#{from}_id", :"#{to}_id"
      rename_column :attempt_actions, :"#{from}_attempt_id", :"#{to}_attempt_id"

      rename_index :"#{to}_attempts", "index_#{from}_attempts_one_open_per_#{from}", "index_#{to}_attempts_one_open_per_#{to}"
      rename_index :"#{to}_attempts", "index_#{from}_attempts_one_scored_per_#{from}", "index_#{to}_attempts_one_scored_per_#{to}"

      RENAMED_CONSTRAINTS.each do |table, names|
        table = table.to_s.sub("mission", to)
        names.each do |name|
          execute "ALTER TABLE #{table} RENAME CONSTRAINT #{from}#{table.delete_prefix(to)}_#{name} TO #{table}_#{name}"
        end
      end
      execute "ALTER TABLE #{to}_attempts RENAME CONSTRAINT #{from}_attempts_status TO #{to}_attempts_status"
    end

    # Swaps a stored value for its new spelling, along with the check constraint that lists the allowed values.
    def rewrite_values(status:, kind:, reason:)
      attempts = connection.table_exists?(:mission_attempts) ? :mission_attempts : :shift_attempts

      replace_check attempts, "#{attempts}_status", "status", STATUSES, *status
      replace_check :attempt_actions, "attempt_actions_kind", "kind", ACTION_KINDS, *kind
      replace_check :xp_events, "xp_events_reason", "reason", XP_REASONS, *reason
    end

    def replace_check(table, name, column, values, from, to)
      remove_check_constraint table, name: name
      execute "UPDATE #{table} SET #{column} = #{quote(to)} WHERE #{column} = #{quote(from)}"
      list = values.map { |value| quote(format(value, to)) }.join(", ")
      add_check_constraint table, "#{column} IN (#{list})", name: name
    end

    # Finished attempts keep a JSON copy of their content (MissionAttempt::ContentSnapshot), whose
    # messages and hints carry the parent's id under the old column name.
    def rewrite_snapshots(from, to)
      table = connection.table_exists?(:mission_attempts) ? :mission_attempts : :shift_attempts
      select_rows("SELECT id, result_content FROM #{table} WHERE result_content <> '{}'::jsonb").each do |id, json|
        content = JSON.parse(json)
        %w[ messages hints ].each do |children|
          Array(content[children]).each { |child| child[to] = child.delete(from) if child.key?(from) }
        end
        execute "UPDATE #{table} SET result_content = #{quote(content.to_json)}::jsonb WHERE id = #{Integer(id)}"
      end
    end

    def quote(value) = connection.quote(value)
end
