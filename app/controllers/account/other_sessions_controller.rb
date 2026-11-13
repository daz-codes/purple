module Account
  # "Sign out everywhere else": revokes every session except the current one.
  class OtherSessionsController < ApplicationController
    def destroy
      Current.user.sessions.where.not(id: Current.session.id).destroy_all
      redirect_to account_path, status: :see_other, notice: "All your other devices have been signed out."
    end
  end
end
