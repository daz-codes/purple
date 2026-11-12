# Game content authored as YAML in content/ and loaded by bin/rails content:import.
# String-backed enums are guarded by check constraints as well as model validations.
class CreateContentTables < ActiveRecord::Migration[8.2]
  def change
    create_table :techniques do |t|
      t.string :key, null: false
      t.string :name, null: false
      t.string :attack_id
      t.string :category, null: false
      t.text :description, null: false
      t.text :defence_tip, null: false
      t.integer :red_cost, null: false, default: 0
      t.integer :stealth, null: false
      t.string :red_flag_label, null: false
      t.timestamps

      t.index :key, unique: true
      t.check_constraint "category IN ('pretext', 'sender', 'lure', 'payload', 'timing')", name: "techniques_category"
      t.check_constraint "stealth BETWEEN 1 AND 10", name: "techniques_stealth_range"
      t.check_constraint "red_cost >= 0", name: "techniques_red_cost_non_negative"
    end

    create_table :tracks do |t|
      t.string :slug, null: false
      t.string :title, null: false
      t.text :description, null: false
      t.integer :position, null: false, default: 0
      t.string :difficulty, null: false
      t.boolean :published, null: false, default: false
      t.timestamps

      t.index :slug, unique: true
      t.check_constraint "difficulty IN ('beginner', 'intermediate', 'advanced')", name: "tracks_difficulty"
    end

    create_table :shifts do |t|
      t.references :track, null: false, foreign_key: true
      t.string :slug, null: false
      t.string :title, null: false
      t.string :kind, null: false
      t.string :difficulty, null: false
      t.integer :time_budget_minutes, null: false
      t.integer :position, null: false, default: 0
      t.boolean :published, null: false, default: false
      t.text :briefing, null: false
      t.text :learning_summary, null: false
      t.string :author_side, null: false, default: "red"
      t.string :author_type, null: false, default: "system"
      t.jsonb :action_costs, null: false, default: {}
      t.timestamps

      t.index :slug, unique: true
      t.check_constraint "kind IN ('inbox', 'messages')", name: "shifts_kind"
      t.check_constraint "difficulty IN ('beginner', 'intermediate', 'advanced')", name: "shifts_difficulty"
      t.check_constraint "author_side IN ('red')", name: "shifts_author_side"
      t.check_constraint "author_type IN ('system', 'player')", name: "shifts_author_type"
      t.check_constraint "time_budget_minutes > 0", name: "shifts_time_budget_positive"
    end

    create_table :tasks do |t|
      t.references :shift, null: false, foreign_key: true
      t.string :key, null: false
      t.string :title, null: false
      t.integer :due_at_minute, null: false
      t.integer :points, null: false
      t.timestamps

      t.index [ :shift_id, :key ], unique: true
      t.check_constraint "due_at_minute > 0", name: "tasks_due_at_minute_positive"
      t.check_constraint "points > 0", name: "tasks_points_positive"
    end

    create_table :messages do |t|
      t.references :shift, null: false, foreign_key: true
      t.string :key, null: false
      t.string :channel, null: false
      t.integer :position, null: false
      t.integer :arrives_at_minute, null: false, default: 0
      t.string :from_name, null: false
      t.string :from_address, null: false
      t.string :reply_to
      t.string :to_address
      t.string :subject
      t.text :body_html, null: false
      t.jsonb :attachments, null: false, default: []
      t.boolean :legit, null: false
      t.text :verify_result
      t.timestamps

      t.index [ :shift_id, :key ], unique: true
      t.check_constraint "channel IN ('email', 'sms', 'chat')", name: "messages_channel"
      t.check_constraint "arrives_at_minute >= 0", name: "messages_arrives_at_minute_non_negative"
    end

    create_table :links do |t|
      t.references :message, null: false, foreign_key: true
      t.references :task, foreign_key: true
      t.string :key, null: false
      t.string :display_url, null: false
      t.string :actual_url, null: false
      t.string :outcome, null: false
      t.string :landing_template, null: false
      t.timestamps

      t.index [ :message_id, :key ], unique: true
      t.check_constraint "outcome IN ('completes_task', 'harmless', 'bait_landing', 'malware')", name: "links_outcome"
      t.check_constraint "landing_template IN ('portal_task', 'harmless', 'credential_harvest', 'malware_download')",
        name: "links_landing_template"
      t.check_constraint "(outcome = 'completes_task') = (task_id IS NOT NULL)", name: "links_task_only_when_completing"
    end

    create_table :red_flags do |t|
      t.references :message, null: false, foreign_key: true
      t.string :key, null: false
      t.string :label, null: false
      t.text :explanation, null: false
      t.string :anchor, null: false
      t.integer :points, null: false
      t.timestamps

      t.index [ :message_id, :key ], unique: true
      t.check_constraint "points > 0", name: "red_flags_points_positive"
    end

    create_table :message_techniques do |t|
      t.references :message, null: false, foreign_key: true, index: false
      t.references :technique, null: false, foreign_key: true
      t.timestamps

      t.index [ :message_id, :technique_id ], unique: true
    end

    create_table :hints do |t|
      t.references :shift, null: false, foreign_key: true, index: false
      t.integer :position, null: false
      t.text :body, null: false
      t.integer :penalty_percent, null: false, default: 20
      t.timestamps

      t.index [ :shift_id, :position ], unique: true
      t.check_constraint "penalty_percent BETWEEN 0 AND 100", name: "hints_penalty_percent_range"
    end

    create_table :badges do |t|
      t.string :key, null: false
      t.string :name, null: false
      t.text :description, null: false
      t.string :side, null: false
      t.integer :position, null: false, default: 0
      t.timestamps

      t.index :key, unique: true
      t.check_constraint "side IN ('blue', 'red', 'purple', 'any')", name: "badges_side"
    end

    create_table :user_badges do |t|
      t.references :user, null: false, foreign_key: true, index: false
      t.references :badge, null: false, foreign_key: true
      t.datetime :awarded_at, null: false
      t.timestamps

      t.index [ :user_id, :badge_id ], unique: true
    end
  end
end
