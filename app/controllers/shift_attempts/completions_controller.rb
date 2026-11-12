# "End shift": the player decides they're done for the day. If it's already over (the clock ran out,
# or another tab ended it), the player is taken to the results either way.
class ShiftAttempts::CompletionsController < ApplicationController
  include ShiftPlay

  def create
    play { @attempt.end_shift }
  end
end
