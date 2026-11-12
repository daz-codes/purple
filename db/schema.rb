# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.2].define(version: 2026_11_12_140000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "citext"
  enable_extension "plpgsql"

  create_table "attempt_actions", force: :cascade do |t|
    t.bigint "shift_attempt_id", null: false
    t.string "kind", null: false
    t.string "target_key"
    t.integer "minute", null: false
    t.integer "cost_minutes", default: 0, null: false
    t.jsonb "result", default: {}, null: false
    t.datetime "created_at", null: false
    t.index ["shift_attempt_id", "id"], name: "index_attempt_actions_on_shift_attempt_id_and_id"
    t.check_constraint "cost_minutes >= 0", name: "attempt_actions_cost_non_negative"
    t.check_constraint "kind::text = ANY (ARRAY['open_message'::character varying, 'expand_headers'::character varying, 'verify_sender'::character varying, 'hover_link'::character varying, 'click_link'::character varying, 'close_landing'::character varying, 'submit_credentials'::character varying, 'open_attachment'::character varying, 'report_message'::character varying, 'flag_element'::character varying, 'complete_task'::character varying, 'use_hint'::character varying, 'wait'::character varying, 'end_shift'::character varying]::text[])", name: "attempt_actions_kind"
    t.check_constraint "minute >= 0", name: "attempt_actions_minute_non_negative"
  end

  create_table "badges", force: :cascade do |t|
    t.string "key", null: false
    t.string "name", null: false
    t.text "description", null: false
    t.string "side", null: false
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_badges_on_key", unique: true
    t.check_constraint "side::text = ANY (ARRAY['blue'::character varying, 'red'::character varying, 'purple'::character varying, 'any'::character varying]::text[])", name: "badges_side"
  end

  create_table "hints", force: :cascade do |t|
    t.bigint "shift_id", null: false
    t.integer "position", null: false
    t.text "body", null: false
    t.integer "penalty_percent", default: 20, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["shift_id", "position"], name: "index_hints_on_shift_id_and_position", unique: true
    t.check_constraint "penalty_percent >= 0 AND penalty_percent <= 100", name: "hints_penalty_percent_range"
  end

  create_table "links", force: :cascade do |t|
    t.bigint "message_id", null: false
    t.bigint "task_id"
    t.string "key", null: false
    t.string "display_url", null: false
    t.string "actual_url", null: false
    t.string "outcome", null: false
    t.string "landing_template", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["message_id", "key"], name: "index_links_on_message_id_and_key", unique: true
    t.index ["message_id"], name: "index_links_on_message_id"
    t.index ["task_id"], name: "index_links_on_task_id"
    t.check_constraint "(outcome::text = 'completes_task'::text) = (task_id IS NOT NULL)", name: "links_task_only_when_completing"
    t.check_constraint "landing_template::text = ANY (ARRAY['portal_task'::character varying, 'harmless'::character varying, 'credential_harvest'::character varying, 'malware_download'::character varying]::text[])", name: "links_landing_template"
    t.check_constraint "outcome::text = ANY (ARRAY['completes_task'::character varying, 'harmless'::character varying, 'bait_landing'::character varying, 'malware'::character varying]::text[])", name: "links_outcome"
  end

  create_table "message_techniques", force: :cascade do |t|
    t.bigint "message_id", null: false
    t.bigint "technique_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["message_id", "technique_id"], name: "index_message_techniques_on_message_id_and_technique_id", unique: true
    t.index ["technique_id"], name: "index_message_techniques_on_technique_id"
  end

  create_table "messages", force: :cascade do |t|
    t.bigint "shift_id", null: false
    t.string "key", null: false
    t.string "channel", null: false
    t.integer "position", null: false
    t.integer "arrives_at_minute", default: 0, null: false
    t.string "from_name", null: false
    t.string "from_address", null: false
    t.string "reply_to"
    t.string "to_address"
    t.string "subject"
    t.text "body_html", null: false
    t.jsonb "attachments", default: [], null: false
    t.boolean "legit", null: false
    t.text "verify_result"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["shift_id", "key"], name: "index_messages_on_shift_id_and_key", unique: true
    t.index ["shift_id"], name: "index_messages_on_shift_id"
    t.check_constraint "arrives_at_minute >= 0", name: "messages_arrives_at_minute_non_negative"
    t.check_constraint "channel::text = ANY (ARRAY['email'::character varying, 'sms'::character varying, 'chat'::character varying]::text[])", name: "messages_channel"
  end

  create_table "red_flags", force: :cascade do |t|
    t.bigint "message_id", null: false
    t.string "key", null: false
    t.string "label", null: false
    t.text "explanation", null: false
    t.string "anchor", null: false
    t.integer "points", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["message_id", "key"], name: "index_red_flags_on_message_id_and_key", unique: true
    t.index ["message_id"], name: "index_red_flags_on_message_id"
    t.check_constraint "points > 0", name: "red_flags_points_positive"
  end

  create_table "sessions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "ip_address"
    t.string "user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "shift_attempts", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "shift_id", null: false
    t.string "token", null: false
    t.string "status", default: "open", null: false
    t.integer "clock_minutes", default: 0, null: false
    t.integer "time_budget_minutes", null: false
    t.integer "productivity_score"
    t.integer "security_score"
    t.integer "score"
    t.integer "hints_used", default: 0, null: false
    t.datetime "started_at", null: false
    t.datetime "completed_at"
    t.boolean "scored", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["shift_id"], name: "index_shift_attempts_on_shift_id"
    t.index ["token"], name: "index_shift_attempts_on_token", unique: true
    t.index ["user_id", "shift_id"], name: "index_shift_attempts_one_open_per_shift", unique: true, where: "((status)::text = 'open'::text)"
    t.index ["user_id", "shift_id"], name: "index_shift_attempts_one_scored_per_shift", unique: true, where: "scored"
    t.index ["user_id"], name: "index_shift_attempts_on_user_id"
    t.check_constraint "(status::text = 'open'::text) = (completed_at IS NULL)", name: "shift_attempts_completed_at_when_finished"
    t.check_constraint "(status::text = 'open'::text) = (score IS NULL)", name: "shift_attempts_score_when_finished"
    t.check_constraint "NOT scored OR status::text <> 'open'::text", name: "shift_attempts_scored_only_when_finished"
    t.check_constraint "clock_minutes <= time_budget_minutes", name: "shift_attempts_clock_within_budget"
    t.check_constraint "clock_minutes >= 0", name: "shift_attempts_clock_non_negative"
    t.check_constraint "hints_used >= 0", name: "shift_attempts_hints_used_non_negative"
    t.check_constraint "status::text = ANY (ARRAY['open'::character varying, 'completed'::character varying, 'timed_out'::character varying]::text[])", name: "shift_attempts_status"
    t.check_constraint "time_budget_minutes > 0", name: "shift_attempts_time_budget_positive"
  end

  create_table "shifts", force: :cascade do |t|
    t.bigint "track_id", null: false
    t.string "slug", null: false
    t.string "title", null: false
    t.string "kind", null: false
    t.string "difficulty", null: false
    t.integer "time_budget_minutes", null: false
    t.integer "position", default: 0, null: false
    t.boolean "published", default: false, null: false
    t.text "briefing", null: false
    t.text "learning_summary", null: false
    t.string "author_side", default: "red", null: false
    t.string "author_type", default: "system", null: false
    t.jsonb "action_costs", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_shifts_on_slug", unique: true
    t.index ["track_id"], name: "index_shifts_on_track_id"
    t.check_constraint "author_side::text = 'red'::text", name: "shifts_author_side"
    t.check_constraint "author_type::text = ANY (ARRAY['system'::character varying, 'player'::character varying]::text[])", name: "shifts_author_type"
    t.check_constraint "difficulty::text = ANY (ARRAY['beginner'::character varying, 'intermediate'::character varying, 'advanced'::character varying]::text[])", name: "shifts_difficulty"
    t.check_constraint "kind::text = ANY (ARRAY['inbox'::character varying, 'messages'::character varying]::text[])", name: "shifts_kind"
    t.check_constraint "time_budget_minutes > 0", name: "shifts_time_budget_positive"
  end

  create_table "tasks", force: :cascade do |t|
    t.bigint "shift_id", null: false
    t.string "key", null: false
    t.string "title", null: false
    t.integer "due_at_minute", null: false
    t.integer "points", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["shift_id", "key"], name: "index_tasks_on_shift_id_and_key", unique: true
    t.index ["shift_id"], name: "index_tasks_on_shift_id"
    t.check_constraint "due_at_minute > 0", name: "tasks_due_at_minute_positive"
    t.check_constraint "points > 0", name: "tasks_points_positive"
  end

  create_table "techniques", force: :cascade do |t|
    t.string "key", null: false
    t.string "name", null: false
    t.string "attack_id"
    t.string "category", null: false
    t.text "description", null: false
    t.text "defence_tip", null: false
    t.integer "red_cost", default: 0, null: false
    t.integer "stealth", null: false
    t.string "red_flag_label", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_techniques_on_key", unique: true
    t.check_constraint "category::text = ANY (ARRAY['pretext'::character varying, 'sender'::character varying, 'lure'::character varying, 'payload'::character varying, 'timing'::character varying]::text[])", name: "techniques_category"
    t.check_constraint "red_cost >= 0", name: "techniques_red_cost_non_negative"
    t.check_constraint "stealth >= 1 AND stealth <= 10", name: "techniques_stealth_range"
  end

  create_table "tracks", force: :cascade do |t|
    t.string "slug", null: false
    t.string "title", null: false
    t.text "description", null: false
    t.integer "position", default: 0, null: false
    t.string "difficulty", null: false
    t.boolean "published", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_tracks_on_slug", unique: true
    t.check_constraint "difficulty::text = ANY (ARRAY['beginner'::character varying, 'intermediate'::character varying, 'advanced'::character varying]::text[])", name: "tracks_difficulty"
  end

  create_table "user_badges", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "badge_id", null: false
    t.datetime "awarded_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["badge_id"], name: "index_user_badges_on_badge_id"
    t.index ["user_id", "badge_id"], name: "index_user_badges_on_user_id_and_badge_id", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.citext "email_address", null: false
    t.string "password_digest", null: false
    t.citext "display_name", null: false
    t.datetime "confirmed_at"
    t.boolean "admin", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["display_name"], name: "index_users_on_display_name", unique: true
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  add_foreign_key "attempt_actions", "shift_attempts"
  add_foreign_key "hints", "shifts"
  add_foreign_key "links", "messages"
  add_foreign_key "links", "tasks"
  add_foreign_key "message_techniques", "messages"
  add_foreign_key "message_techniques", "techniques"
  add_foreign_key "messages", "shifts"
  add_foreign_key "red_flags", "messages"
  add_foreign_key "sessions", "users"
  add_foreign_key "shift_attempts", "shifts"
  add_foreign_key "shift_attempts", "users"
  add_foreign_key "shifts", "tracks"
  add_foreign_key "tasks", "shifts"
  add_foreign_key "user_badges", "badges"
  add_foreign_key "user_badges", "users"
end
