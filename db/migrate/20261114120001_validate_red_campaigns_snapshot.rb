class ValidateRedCampaignsSnapshot < ActiveRecord::Migration[8.2]
  def change
    validate_check_constraint :red_campaigns, name: "red_campaigns_snapshot_when_launched"
  end
end
