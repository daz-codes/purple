# Phase 2 (P1): signals missions, the Codebreaking and Forensics paths' kind. Each holds a queue of
# intercepts; each intercept gives up a flag the player submits as text, checked on the server against
# stored digests. The intercept's file (a photo, a document) is stored with it, so the Workbench can
# read it from the attempt. A daily track holds the Intercept of the day's pool.
#
# safety_assured: missions, tracks and attempt_actions' kind list are content tables or a check-list
# swap on small tables (the same pattern as the earlier kind changes), with no long locks.
class AddSignalsMissions < ActiveRecord::Migration[8.2]
  ACTION_KINDS = %w[ open_message expand_headers verify_sender click_link close_landing submit_credentials
                     open_attachment run_download use_portal report_message archive_message flag_element
                     send_reply use_hint stand_down save_note share_details ask_why ].freeze

  def up
    create_table :intercepts do |t|
      t.references :mission, null: false, foreign_key: true, index: false
      t.string :key, null: false
      t.integer :position, null: false
      t.string :title, null: false
      t.string :source, null: false
      t.text :question, null: false
      t.text :body
      t.string :file_name
      t.string :file_type
      t.binary :file_data
      t.text :solution, null: false
      t.text :explanation, null: false
      t.jsonb :flag_digests, null: false, default: []
      t.jsonb :recipe, null: false, default: []
      t.integer :points, null: false, default: 100
      t.timestamps

      t.index %i[ mission_id key ], unique: true
      t.index %i[ mission_id position ], unique: true
      t.check_constraint "(body IS NULL) <> (file_data IS NULL)", name: "intercepts_body_or_file"
      t.check_constraint "(file_data IS NULL) = (file_name IS NULL) AND (file_data IS NULL) = (file_type IS NULL)",
        name: "intercepts_file_complete"
      t.check_constraint "file_type IS NULL OR file_type IN ('image/png', 'application/pdf', 'text/plain')", name: "intercepts_file_type"
      t.check_constraint "jsonb_typeof(flag_digests) = 'array' AND jsonb_array_length(flag_digests) > 0", name: "intercepts_flag_digests"
      t.check_constraint "points > 0", name: "intercepts_points_positive"
    end

    safety_assured do
      remove_check_constraint :missions, name: "missions_kind"
      add_check_constraint :missions, "kind IN ('inbox', 'messages', 'signals')", name: "missions_kind"

      remove_check_constraint :attempt_actions, name: "attempt_actions_kind"
      add_check_constraint :attempt_actions, "kind IN (#{(ACTION_KINDS + %w[ submit_flag ]).map { |kind| "'#{kind}'" }.join(", ")})",
        name: "attempt_actions_kind"

      add_column :tracks, :daily, :boolean, null: false, default: false
    end
  end

  def down
    safety_assured do
      execute "DELETE FROM attempt_actions WHERE kind = 'submit_flag'"
      remove_check_constraint :attempt_actions, name: "attempt_actions_kind"
      add_check_constraint :attempt_actions, "kind IN (#{ACTION_KINDS.map { |kind| "'#{kind}'" }.join(", ")})", name: "attempt_actions_kind"

      remove_column :tracks, :daily
      drop_table :intercepts
      remove_check_constraint :missions, name: "missions_kind"
      add_check_constraint :missions, "kind IN ('inbox', 'messages')", name: "missions_kind"
    end
  end
end
