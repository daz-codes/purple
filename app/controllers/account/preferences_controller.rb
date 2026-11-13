module Account
  # The player's settings, shown on the account page. For now, relaxed mode: shifts without timing.
  class PreferencesController < ApplicationController
    def update
      Current.user.update!(params.expect(user: [ :relaxed_mode ]))
      redirect_to account_path, status: :see_other, notice: "Settings saved."
    end
  end
end
