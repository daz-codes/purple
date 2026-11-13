# M6b, after review: "Give up" is "Clock off early", which fits a working day.
class RenameGiveUpToClockOff < ActiveRecord::Migration[8.2]
  KINDS = %w[
    open_message expand_headers verify_sender click_link close_landing submit_credentials open_attachment
    run_download use_portal report_message archive_message flag_element send_reply use_hint
  ].freeze

  def up
    rename_values("give_up" => "clock_off", "gave_up" => "clocked_off")
  end

  def down
    rename_values("clock_off" => "give_up", "clocked_off" => "gave_up")
  end

  private
    def rename_values(renames)
      kind_from, kind_to = renames.first
      status_from, status_to = renames.to_a.last

      safety_assured do
        remove_check_constraint :attempt_actions, name: "attempt_actions_kind"
        remove_check_constraint :shift_attempts, name: "shift_attempts_status"
        execute "UPDATE attempt_actions SET kind = '#{kind_to}' WHERE kind = '#{kind_from}'"
        execute "UPDATE shift_attempts SET status = '#{status_to}' WHERE status = '#{status_from}'"
        add_check_constraint :attempt_actions, "kind IN (#{(KINDS + [ kind_to ]).map { |kind| "'#{kind}'" }.join(", ")})",
          name: "attempt_actions_kind"
        add_check_constraint :shift_attempts, "status IN ('open', 'completed', '#{status_to}', 'timed_out')", name: "shift_attempts_status"
      end
    end
end
