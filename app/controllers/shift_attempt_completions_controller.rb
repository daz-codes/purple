# "End shift": the player decides they're done for the day.
class ShiftAttemptCompletionsController < ApplicationController
  include ShiftAttemptScoped

  def create
    end_shift
    redirect_to @attempt, status: :see_other
  end

  private
    def end_shift
      Shift::Engine.new(@attempt).end_shift
    rescue Shift::Engine::Rejected
      # Already over: the clock ran out, or another tab ended it. Show the results either way.
    end
end
