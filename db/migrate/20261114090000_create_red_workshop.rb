# M7: Red's Workshop. Targets (a recon brief on one of Blue's companies), the cards Red can pick for
# each, the Blue bots that judge Red's email, and Red's campaigns.
class CreateRedWorkshop < ActiveRecord::Migration[8.2]
  CATEGORIES = %w[ pretext sender lure payload timing ].freeze

  def change
    create_table :bot_personas do |t|
      t.string :key, null: false, index: { unique: true }
      t.string :name, null: false
      t.text :description, null: false
      t.integer :vigilance, null: false
      t.jsonb :detects, null: false, default: {}
      t.integer :position, null: false, default: 0
      t.timestamps
      t.check_constraint "vigilance BETWEEN 1 AND 10", name: "bot_personas_vigilance_range"
    end

    create_table :targets do |t|
      t.references :shift, null: false, foreign_key: true
      t.string :slug, null: false, index: { unique: true }
      t.string :title, null: false
      t.text :recon_brief, null: false
      t.integer :budget, null: false
      t.integer :position, null: false, default: 0
      t.boolean :published, null: false, default: true
      t.timestamps
      t.check_constraint "budget > 0", name: "targets_budget_positive"
    end

    create_table :target_options do |t|
      t.references :target, null: false, foreign_key: true
      t.references :technique, null: false, foreign_key: true
      t.string :key, null: false
      t.string :category, null: false
      t.string :label, null: false
      t.string :subject
      t.text :rendered_value, null: false
      t.integer :relevance, null: false, default: 0
      t.integer :extra_cost, null: false, default: 0
      t.integer :position, null: false, default: 0
      t.timestamps
      t.index %i[ target_id key ], unique: true
      t.check_constraint "category IN (#{CATEGORIES.map { |category| "'#{category}'" }.join(", ")})", name: "target_options_category"
      t.check_constraint "relevance BETWEEN 0 AND 3", name: "target_options_relevance_range"
      t.check_constraint "extra_cost >= 0", name: "target_options_extra_cost_non_negative"
      t.check_constraint "(category = 'pretext') = (subject IS NOT NULL)", name: "target_options_subject_only_for_pretexts"
    end

    create_table :red_campaigns do |t|
      t.references :user, null: false, foreign_key: true
      t.references :target, null: false, foreign_key: true
      t.string :token, null: false, index: { unique: true }
      t.string :status, null: false, default: "draft"
      t.bigint :chosen_option_ids, array: true, null: false, default: []
      t.integer :budget_spent, null: false, default: 0
      t.string :rendered_subject
      t.string :rendered_from
      t.text :rendered_body_html
      t.jsonb :results, null: false, default: []
      t.integer :score
      t.boolean :scored, null: false, default: false
      t.integer :seed, null: false
      t.datetime :launched_at
      t.timestamps
      t.index %i[ user_id target_id ], unique: true, where: "scored", name: "index_red_campaigns_one_scored_per_target"
      t.index %i[ user_id target_id ], unique: true, where: "status = 'draft'", name: "index_red_campaigns_one_draft_per_target"
      t.check_constraint "status IN ('draft', 'launched')", name: "red_campaigns_status"
      t.check_constraint "(status = 'launched') = (launched_at IS NOT NULL)", name: "red_campaigns_launched_at_when_launched"
      t.check_constraint "(status = 'launched') = (score IS NOT NULL)", name: "red_campaigns_score_when_launched"
      t.check_constraint "NOT scored OR status = 'launched'", name: "red_campaigns_scored_only_when_launched"
      t.check_constraint "budget_spent >= 0", name: "red_campaigns_budget_spent_non_negative"
    end
  end
end
