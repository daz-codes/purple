# M4: running a downloaded file (from a malware link or a disguised attachment) is its own move,
# separate from opening the attachment, because it's the moment the player is compromised.
class AddRunDownloadToAttemptActions < ActiveRecord::Migration[8.2]
  KINDS = %w[
    open_message expand_headers verify_sender hover_link click_link close_landing submit_credentials
    open_attachment run_download report_message flag_element complete_task use_hint wait end_shift
  ].freeze

  def up
    remove_check_constraint :attempt_actions, name: "attempt_actions_kind"
    add_check_constraint :attempt_actions, "kind IN (#{KINDS.map { |kind| "'#{kind}'" }.join(", ")})",
      name: "attempt_actions_kind", validate: false
  end

  def down
    remove_check_constraint :attempt_actions, name: "attempt_actions_kind"
    add_check_constraint :attempt_actions, "kind IN (#{(KINDS - %w[ run_download ]).map { |kind| "'#{kind}'" }.join(", ")})",
      name: "attempt_actions_kind", validate: false
  end
end
