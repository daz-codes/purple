# M7b: private details. A genuine message says which details it needs, a phish which it wants, and a
# message can hold details the player learns (quoted in its text, like a red flag). New moves: saving a
# note, sharing details, and asking why someone needs them.
#
# Nothing has been deployed yet (that's M10), so replacing the kind constraint only touches development
# and test data.
class AddPrivateDetails < ActiveRecord::Migration[8.2]
  ACTION_KINDS = %w[
    open_message expand_headers verify_sender click_link close_landing submit_credentials open_attachment
    run_download use_portal report_message archive_message flag_element send_reply use_hint clock_off
    save_note share_details ask_why
  ].freeze

  def up
    add_column :messages, :needs, :jsonb, null: false, default: []
    add_column :messages, :wants, :jsonb, null: false, default: []
    add_column :messages, :details, :jsonb, null: false, default: []
    add_column :messages, :share_response, :text

    safety_assured do
      remove_check_constraint :attempt_actions, name: "attempt_actions_kind"
      add_check_constraint :attempt_actions, "kind IN (#{ACTION_KINDS.map { |kind| "'#{kind}'" }.join(", ")})", name: "attempt_actions_kind"
    end
  end

  def down
    safety_assured do
      execute "DELETE FROM attempt_actions WHERE kind IN ('save_note', 'share_details', 'ask_why')"
      remove_check_constraint :attempt_actions, name: "attempt_actions_kind"
      add_check_constraint :attempt_actions, "kind IN (#{(ACTION_KINDS - %w[ save_note share_details ask_why ]).map { |kind| "'#{kind}'" }.join(", ")})",
        name: "attempt_actions_kind"
    end
    remove_column :messages, :share_response
    remove_column :messages, :details
    remove_column :messages, :wants
    remove_column :messages, :needs
  end
end
