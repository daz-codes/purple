# M6: a text or chat message can offer canned replies. Each is { "id", "text", "outcome", "response" };
# the outcome stays on the server, like an attachment's. Sending one is its own move: send_reply.
class AddRepliesToMessages < ActiveRecord::Migration[8.2]
  KINDS = %w[
    open_message expand_headers verify_sender hover_link click_link close_landing submit_credentials
    open_attachment run_download report_message flag_element complete_task use_hint wait end_shift send_reply
  ].freeze

  def up
    add_column :messages, :replies, :jsonb, default: [], null: false

    remove_check_constraint :attempt_actions, name: "attempt_actions_kind"
    add_check_constraint :attempt_actions, kinds_constraint(KINDS), name: "attempt_actions_kind", validate: false
  end

  def down
    remove_check_constraint :attempt_actions, name: "attempt_actions_kind"
    add_check_constraint :attempt_actions, kinds_constraint(KINDS - %w[ send_reply ]), name: "attempt_actions_kind", validate: false

    remove_column :messages, :replies
  end

  private
    def kinds_constraint(kinds)
      "kind IN (#{kinds.map { |kind| "'#{kind}'" }.join(", ")})"
    end
end
