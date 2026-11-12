# Pressing "Sign in" on a lookalike page. The form's fields have no names, so nothing typed reaches
# the server; it only learns that the button was pressed.
class ShiftAttempts::Tabs::SignInsController < ApplicationController
  include ShiftPlay

  def create
    play(alert: "Your account just sent 400 emails to your contacts. IT has locked it while they clean up. " \
                "Keep working, but that password belongs to someone else now.") do
      @attempt.submit_credentials
    end
  end
end
