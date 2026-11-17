# Closing the page open in the in-game browser.
class MissionAttempts::TabsController < ApplicationController
  include MissionPlay

  def destroy
    play { @attempt.close_tab }
  end
end
