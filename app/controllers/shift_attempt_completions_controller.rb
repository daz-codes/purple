# "End shift": the player decides they're done for the day.
class ShiftAttemptCompletionsController < ApplicationController
  include ShiftAttemptScoped
  rate_limit to: 10, within: 1.minute,
    with: -> { redirect_to @attempt || tracks_path, alert: "Slow down a moment and try again." }

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
