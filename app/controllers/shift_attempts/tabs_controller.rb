# Closing the page open in the in-game browser.
class ShiftAttempts::TabsController < ApplicationController
  include ShiftPlay

  def destroy
    play { @attempt.close_tab }
  end
end
