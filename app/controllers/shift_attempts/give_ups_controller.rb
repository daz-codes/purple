# "Give up": the player ends the shift before every message has been dealt with. What's left counts
# as ignored. If it's already over (another tab finished it), the player is taken to the debrief.
class ShiftAttempts::GiveUpsController < ApplicationController
  include ShiftPlay

  def create
    play { @attempt.give_up }
  end
end
