module Account
  # The player's settings. For now, relaxed mode: shifts without timing.
  class PreferencesController < ApplicationController
    def edit
    end

    def update
      Current.user.update!(params.expect(user: [ :relaxed_mode ]))
      redirect_to edit_account_preferences_path, status: :see_other, notice: "Settings saved."
    end
  end
end
