# Phase 2 (P0): every track belongs to a path, a skill area such as Phishing or Codebreaking. A path
# records how it opens, and a track how many missions on the track before must be finished first. P1
# enforces both; until then everything published stays open.
#
# The three phase 1 tracks move into the Phishing path. It's created here, so existing tracks can
# take a path before the column becomes NOT NULL; the next content import fills in its details.
#
# safety_assured: paths and tracks are content tables, rewritten by every import and a handful of
# rows each, so the index, foreign key and NOT NULL on tracks hold no lock worth worrying about.
class CreatePaths < ActiveRecord::Migration[8.2]
  def up
    create_table :paths do |t|
      t.string :slug, null: false, index: { unique: true }
      t.string :title, null: false
      t.text :description, null: false
      t.integer :position, null: false, default: 0
      t.boolean :published, null: false, default: false
      t.string :opens, null: false, default: "always"
      t.integer :opens_after_missions
      t.references :opens_after_path, foreign_key: { to_table: :paths }
      t.timestamps

      t.check_constraint "opens IN ('always', 'after_missions', 'after_first_track')", name: "paths_opens"
      t.check_constraint "(opens = 'after_missions') = (opens_after_missions IS NOT NULL)", name: "paths_opens_after_missions"
      t.check_constraint "opens_after_missions IS NULL OR opens_after_missions > 0", name: "paths_opens_after_missions_positive"
      t.check_constraint "(opens = 'after_first_track') = (opens_after_path_id IS NOT NULL)", name: "paths_opens_after_path"
      t.check_constraint "opens_after_path_id IS NULL OR opens_after_path_id <> id", name: "paths_opens_after_another_path"
    end

    safety_assured do
      add_reference :tracks, :path, foreign_key: true
      add_column :tracks, :unlock_after, :integer, null: false, default: 0
      add_check_constraint :tracks, "unlock_after >= 0", name: "tracks_unlock_after_non_negative"

      execute <<~SQL
        INSERT INTO paths (slug, title, description, position, published, opens, created_at, updated_at)
        SELECT 'phishing', 'Phishing', 'Spotting and resisting social engineering.', 1, true, 'always', now(), now()
        WHERE EXISTS (SELECT 1 FROM tracks)
      SQL
      execute "UPDATE tracks SET path_id = (SELECT id FROM paths WHERE slug = 'phishing')"
      change_column_null :tracks, :path_id, false
    end
  end

  def down
    remove_reference :tracks, :path, foreign_key: true
    remove_column :tracks, :unlock_after
    drop_table :paths
  end
end
