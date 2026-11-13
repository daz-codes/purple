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

ActiveRecord::Schema[8.2].define(version: 2026_11_14_150000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "citext"
  enable_extension "plpgsql"

  create_table "attempt_actions", force: :cascade do |t|
    t.bigint "shift_attempt_id", null: false
    t.string "kind", null: false
    t.string "target_key"
    t.jsonb "result", default: {}, null: false
    t.datetime "created_at", null: false
    t.integer "at_seconds", default: 0, null: false
    t.integer "penalty_seconds", default: 0, null: false
    t.index ["shift_attempt_id", "id"], name: "index_attempt_actions_on_shift_attempt_id_and_id"
    t.check_constraint "at_seconds >= 0", name: "attempt_actions_at_seconds_non_negative"
    t.check_constraint "kind::text = ANY (ARRAY['open_message'::character varying::text, 'expand_headers'::character varying::text, 'verify_sender'::character varying::text, 'click_link'::character varying::text, 'close_landing'::character varying::text, 'submit_credentials'::character varying::text, 'open_attachment'::character varying::text, 'run_download'::character varying::text, 'use_portal'::character varying::text, 'report_message'::character varying::text, 'archive_message'::character varying::text, 'flag_element'::character varying::text, 'send_reply'::character varying::text, 'use_hint'::character varying::text, 'clock_off'::character varying::text])", name: "attempt_actions_kind"
    t.check_constraint "penalty_seconds >= 0", name: "attempt_actions_penalty_seconds_non_negative"
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
    t.check_constraint "side::text = ANY (ARRAY['blue'::character varying::text, 'red'::character varying::text, 'purple'::character varying::text, 'any'::character varying::text])", name: "badges_side"
  end

  create_table "bot_personas", force: :cascade do |t|
    t.string "key", null: false
    t.string "name", null: false
    t.text "description", null: false
    t.integer "vigilance", null: false
    t.jsonb "detects", default: {}, null: false
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_bot_personas_on_key", unique: true
    t.check_constraint "vigilance >= 1 AND vigilance <= 10", name: "bot_personas_vigilance_range"
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
    t.string "key", null: false
    t.string "display_url", null: false
    t.string "actual_url", null: false
    t.string "outcome", null: false
    t.string "landing_template", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "portal_action"
    t.index ["message_id", "key"], name: "index_links_on_message_id_and_key", unique: true
    t.index ["message_id"], name: "index_links_on_message_id"
    t.check_constraint "(outcome::text = 'portal'::text) = (portal_action IS NOT NULL)", name: "links_portal_action_only_on_portals"
    t.check_constraint "landing_template::text = ANY (ARRAY['portal'::character varying::text, 'harmless'::character varying::text, 'credential_harvest'::character varying::text, 'malware_download'::character varying::text])", name: "links_landing_template"
    t.check_constraint "outcome::text = ANY (ARRAY['portal'::character varying::text, 'harmless'::character varying::text, 'bait_landing'::character varying::text, 'malware'::character varying::text])", name: "links_outcome"
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
    t.jsonb "replies", default: [], null: false
    t.integer "arrives_after_handled"
    t.string "arrives_after"
    t.string "expects"
    t.integer "points", default: 0, null: false
    t.integer "urgent_within_minutes"
    t.string "answer_in_key"
    t.text "answer_in_quote"
    t.index ["shift_id", "key"], name: "index_messages_on_shift_id_and_key", unique: true
    t.index ["shift_id"], name: "index_messages_on_shift_id"
    t.check_constraint "(answer_in_key IS NULL) = (answer_in_quote IS NULL)", name: "messages_answer_in_complete"
    t.check_constraint "\nCASE\n    WHEN legit THEN points > 0\n    ELSE points = 0\nEND", name: "messages_points_only_when_genuine"
    t.check_constraint "answer_in_key IS NULL OR legit AND expects::text = 'reply'::text", name: "messages_answer_in_only_when_asking"
    t.check_constraint "arrives_after_handled > 0", name: "messages_arrives_after_handled_positive"
    t.check_constraint "arrives_after_handled IS NULL OR arrives_after IS NULL", name: "messages_one_arrival_trigger"
    t.check_constraint "channel::text = ANY (ARRAY['email'::character varying::text, 'sms'::character varying::text, 'chat'::character varying::text])", name: "messages_channel"
    t.check_constraint "expects::text = ANY (ARRAY['reply'::character varying::text, 'act'::character varying::text, 'archive'::character varying::text])", name: "messages_expects"
    t.check_constraint "legit = (expects IS NOT NULL)", name: "messages_expects_only_when_genuine"
    t.check_constraint "urgent_within_minutes IS NULL OR legit AND urgent_within_minutes > 0", name: "messages_urgent_only_when_genuine"
  end

  create_table "red_campaigns", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "target_id", null: false
    t.string "token", null: false
    t.string "status", default: "draft", null: false
    t.bigint "chosen_option_ids", default: [], null: false, array: true
    t.integer "budget_spent", default: 0, null: false
    t.string "rendered_subject"
    t.string "rendered_from"
    t.text "rendered_body_html"
    t.jsonb "results", default: [], null: false
    t.integer "score"
    t.boolean "scored", default: false, null: false
    t.integer "seed", null: false
    t.datetime "launched_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "budget"
    t.integer "max_score"
    t.index ["target_id"], name: "index_red_campaigns_on_target_id"
    t.index ["token"], name: "index_red_campaigns_on_token", unique: true
    t.index ["user_id", "target_id"], name: "index_red_campaigns_one_draft_per_target", unique: true, where: "((status)::text = 'draft'::text)"
    t.index ["user_id", "target_id"], name: "index_red_campaigns_one_scored_per_target", unique: true, where: "scored"
    t.index ["user_id"], name: "index_red_campaigns_on_user_id"
    t.check_constraint "(status::text = 'launched'::text) = (budget IS NOT NULL AND max_score IS NOT NULL)", name: "red_campaigns_snapshot_when_launched"
    t.check_constraint "(status::text = 'launched'::text) = (launched_at IS NOT NULL)", name: "red_campaigns_launched_at_when_launched"
    t.check_constraint "(status::text = 'launched'::text) = (score IS NOT NULL)", name: "red_campaigns_score_when_launched"
    t.check_constraint "NOT scored OR status::text = 'launched'::text", name: "red_campaigns_scored_only_when_launched"
    t.check_constraint "budget_spent >= 0", name: "red_campaigns_budget_spent_non_negative"
    t.check_constraint "status::text = ANY (ARRAY['draft'::character varying::text, 'launched'::character varying::text])", name: "red_campaigns_status"
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
    t.string "quote"
    t.integer "quote_start"
    t.integer "quote_end"
    t.string "contradicts_key"
    t.text "contradicts_quote"
    t.index ["message_id", "key"], name: "index_red_flags_on_message_id_and_key", unique: true
    t.index ["message_id"], name: "index_red_flags_on_message_id"
    t.check_constraint "(contradicts_key IS NULL) = (contradicts_quote IS NULL)", name: "red_flags_contradicts_complete"
    t.check_constraint "points > 0", name: "red_flags_points_positive"
    t.check_constraint "quote IS NULL AND quote_start IS NULL AND quote_end IS NULL OR quote IS NOT NULL AND quote_start >= 0 AND quote_end > quote_start", name: "red_flags_quote_complete"
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
    t.integer "score"
    t.datetime "started_at", null: false
    t.datetime "completed_at"
    t.boolean "scored", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "penalty_seconds", default: 0, null: false
    t.boolean "relaxed", default: false, null: false
    t.index ["shift_id"], name: "index_shift_attempts_on_shift_id"
    t.index ["token"], name: "index_shift_attempts_on_token", unique: true
    t.index ["user_id", "shift_id"], name: "index_shift_attempts_one_open_per_shift", unique: true, where: "((status)::text = 'open'::text)"
    t.index ["user_id", "shift_id"], name: "index_shift_attempts_one_scored_per_shift", unique: true, where: "scored"
    t.index ["user_id"], name: "index_shift_attempts_on_user_id"
    t.check_constraint "(status::text = 'open'::text) = (completed_at IS NULL)", name: "shift_attempts_completed_at_when_finished"
    t.check_constraint "(status::text = 'open'::text) = (score IS NULL)", name: "shift_attempts_score_when_finished"
    t.check_constraint "NOT scored OR status::text <> 'open'::text", name: "shift_attempts_scored_only_when_finished"
    t.check_constraint "penalty_seconds >= 0", name: "shift_attempts_penalty_seconds_non_negative"
    t.check_constraint "status::text = ANY (ARRAY['open'::character varying::text, 'completed'::character varying::text, 'clocked_off'::character varying::text, 'timed_out'::character varying::text])", name: "shift_attempts_status"
  end

  create_table "shifts", force: :cascade do |t|
    t.bigint "track_id", null: false
    t.string "slug", null: false
    t.string "title", null: false
    t.string "kind", null: false
    t.string "difficulty", null: false
    t.integer "position", default: 0, null: false
    t.boolean "published", default: false, null: false
    t.text "briefing", null: false
    t.text "learning_summary", null: false
    t.string "author_side", default: "red", null: false
    t.string "author_type", default: "system", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "par_minutes", default: 10, null: false
    t.index ["slug"], name: "index_shifts_on_slug", unique: true
    t.index ["track_id"], name: "index_shifts_on_track_id"
    t.check_constraint "author_side::text = 'red'::text", name: "shifts_author_side"
    t.check_constraint "author_type::text = ANY (ARRAY['system'::character varying::text, 'player'::character varying::text])", name: "shifts_author_type"
    t.check_constraint "difficulty::text = ANY (ARRAY['beginner'::character varying::text, 'intermediate'::character varying::text, 'advanced'::character varying::text])", name: "shifts_difficulty"
    t.check_constraint "kind::text = ANY (ARRAY['inbox'::character varying::text, 'messages'::character varying::text])", name: "shifts_kind"
    t.check_constraint "par_minutes > 0", name: "shifts_par_minutes_positive"
  end

  create_table "target_options", force: :cascade do |t|
    t.bigint "target_id", null: false
    t.bigint "technique_id", null: false
    t.string "key", null: false
    t.string "category", null: false
    t.string "label", null: false
    t.string "subject"
    t.text "rendered_value", null: false
    t.integer "relevance", default: 0, null: false
    t.integer "extra_cost", default: 0, null: false
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["target_id", "key"], name: "index_target_options_on_target_id_and_key", unique: true
    t.index ["target_id"], name: "index_target_options_on_target_id"
    t.index ["technique_id"], name: "index_target_options_on_technique_id"
    t.check_constraint "(category::text = 'pretext'::text) = (subject IS NOT NULL)", name: "target_options_subject_only_for_pretexts"
    t.check_constraint "category::text = ANY (ARRAY['pretext'::character varying::text, 'sender'::character varying::text, 'lure'::character varying::text, 'payload'::character varying::text, 'timing'::character varying::text])", name: "target_options_category"
    t.check_constraint "extra_cost >= 0", name: "target_options_extra_cost_non_negative"
    t.check_constraint "relevance >= 0 AND relevance <= 3", name: "target_options_relevance_range"
  end

  create_table "targets", force: :cascade do |t|
    t.bigint "shift_id", null: false
    t.string "slug", null: false
    t.string "title", null: false
    t.text "recon_brief", null: false
    t.integer "budget", null: false
    t.integer "position", default: 0, null: false
    t.boolean "published", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["shift_id"], name: "index_targets_on_shift_id"
    t.index ["slug"], name: "index_targets_on_slug", unique: true
    t.check_constraint "budget > 0", name: "targets_budget_positive"
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
    t.check_constraint "category::text = ANY (ARRAY['pretext'::character varying::text, 'sender'::character varying::text, 'lure'::character varying::text, 'payload'::character varying::text, 'timing'::character varying::text])", name: "techniques_category"
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
    t.check_constraint "difficulty::text = ANY (ARRAY['beginner'::character varying::text, 'intermediate'::character varying::text, 'advanced'::character varying::text])", name: "tracks_difficulty"
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
    t.boolean "relaxed_mode", default: false, null: false
    t.string "preferred_side"
    t.integer "blue_xp", default: 0, null: false
    t.integer "red_xp", default: 0, null: false
    t.integer "blue_level", default: 1, null: false
    t.integer "red_level", default: 1, null: false
    t.integer "xp_total", default: 0, null: false
    t.integer "current_streak", default: 0, null: false
    t.integer "longest_streak", default: 0, null: false
    t.date "last_played_on"
    t.boolean "leaderboard_opt_out", default: false, null: false
    t.index ["display_name"], name: "index_users_on_display_name", unique: true
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
    t.check_constraint "blue_level >= 1 AND red_level >= 1", name: "users_levels_positive"
    t.check_constraint "blue_xp >= 0 AND red_xp >= 0", name: "users_xp_non_negative"
    t.check_constraint "current_streak >= 0 AND longest_streak >= current_streak", name: "users_streaks"
    t.check_constraint "preferred_side::text = ANY (ARRAY['blue'::character varying::text, 'red'::character varying::text])", name: "users_preferred_side"
    t.check_constraint "xp_total = (blue_xp + red_xp)", name: "users_xp_total_is_the_sum"
  end

  create_table "xp_events", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "side", null: false
    t.integer "amount", null: false
    t.string "reason", null: false
    t.string "source_type"
    t.bigint "source_id"
    t.datetime "occurred_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "relaxed", default: false, null: false
    t.index ["side", "occurred_at"], name: "index_xp_events_on_side_and_occurred_at"
    t.index ["source_type", "source_id"], name: "index_xp_events_on_source"
    t.index ["user_id", "occurred_at"], name: "index_xp_events_on_user_id_and_occurred_at"
    t.index ["user_id", "reason", "source_type", "source_id"], name: "index_xp_events_once_per_source", unique: true
    t.index ["user_id"], name: "index_xp_events_on_user_id"
    t.check_constraint "amount >= 0", name: "xp_events_amount_non_negative"
    t.check_constraint "reason::text = ANY (ARRAY['shift_completed'::character varying::text, 'workshop_completed'::character varying::text, 'streak_bonus'::character varying::text, 'badge_awarded'::character varying::text])", name: "xp_events_reason"
    t.check_constraint "side::text = ANY (ARRAY['blue'::character varying::text, 'red'::character varying::text])", name: "xp_events_side"
  end

  add_foreign_key "attempt_actions", "shift_attempts"
  add_foreign_key "hints", "shifts"
  add_foreign_key "links", "messages"
  add_foreign_key "message_techniques", "messages"
  add_foreign_key "message_techniques", "techniques"
  add_foreign_key "messages", "shifts"
  add_foreign_key "red_campaigns", "targets"
  add_foreign_key "red_campaigns", "users"
  add_foreign_key "red_flags", "messages"
  add_foreign_key "sessions", "users"
  add_foreign_key "shift_attempts", "shifts"
  add_foreign_key "shift_attempts", "users"
  add_foreign_key "shifts", "tracks"
  add_foreign_key "target_options", "targets"
  add_foreign_key "target_options", "techniques"
  add_foreign_key "targets", "shifts"
  add_foreign_key "user_badges", "badges"
  add_foreign_key "user_badges", "users"
  add_foreign_key "xp_events", "users"
end
