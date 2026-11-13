# M7 review: a launched campaign keeps the budget and best possible score it was judged against, so a
# later content import can't rewrite its results.
class SnapshotRedCampaignResults < ActiveRecord::Migration[8.2]
  def change
    add_column :red_campaigns, :budget, :integer
    add_column :red_campaigns, :max_score, :integer
    add_check_constraint :red_campaigns, "(status = 'launched') = (budget IS NOT NULL AND max_score IS NOT NULL)",
      name: "red_campaigns_snapshot_when_launched", validate: false
  end
end
