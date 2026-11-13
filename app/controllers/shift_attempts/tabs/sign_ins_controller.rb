# Pressing "Sign in" on a lookalike page. The form's fields have no names, so nothing typed reaches
# the server; it only learns that the button was pressed, and which chips were picked for any other
# fields the page asks for. The page carries on to a plain confirmation:
# whether that was a mistake waits for the debrief.
class ShiftAttempts::Tabs::SignInsController < ApplicationController
  include ShiftPlay

  def create
    play { @attempt.submit_credentials(details: Array(params[:details])) }
  end
end
