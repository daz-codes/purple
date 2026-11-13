module Account
  # Revokes one of the signed-in user's sessions (one per device). They're listed on the account page.
  class SessionsController < ApplicationController
    def destroy
      session_record = Current.user.sessions.find(params[:id])

      if session_record == Current.session
        terminate_session
        redirect_to new_session_path, status: :see_other, notice: "You've been signed out."
      else
        session_record.destroy!
        redirect_to account_path, status: :see_other, notice: "That device has been signed out."
      end
    end
  end
end
