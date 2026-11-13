# Pressing "Sign in" on a lookalike page. The form's fields have no names, so nothing typed reaches
# the server; it only learns that the button was pressed. The page carries on to a plain confirmation:
# whether that was a mistake waits for the debrief.
class ShiftAttempts::Tabs::SignInsController < ApplicationController
  include ShiftPlay

  def create
    play { @attempt.submit_credentials }
  end
end
