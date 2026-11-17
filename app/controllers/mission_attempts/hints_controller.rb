# Reveals the mission's next hint.
class MissionAttempts::HintsController < ApplicationController
  include MissionPlay

  def create
    play { @attempt.use_hint }
  end
end
