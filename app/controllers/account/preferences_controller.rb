module Account
  # The player's settings, shown on the account page: relaxed mode (shifts without timing) and whether
  # they appear on the leaderboards.
  class PreferencesController < ApplicationController
    def update
      Current.user.update!(params.expect(user: %i[ relaxed_mode leaderboard_opt_out ]))
      redirect_to account_path, status: :see_other, notice: "Settings saved."
    end
  end
end
