class ValidateProgressionConstraints < ActiveRecord::Migration[8.2]
  def change
    %w[ users_preferred_side users_xp_total_is_the_sum users_xp_non_negative users_levels_positive users_streaks ].each do |name|
      validate_check_constraint :users, name:
    end
  end
end
