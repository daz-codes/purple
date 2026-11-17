# "Stand down": the player ends the mission before every message has been dealt with. What's left counts
# as ignored. If it's already over (another tab finished it), the player is taken to the debrief.
class MissionAttempts::StandDownsController < ApplicationController
  include MissionPlay

  def create
    play { @attempt.stand_down }
  end
end
