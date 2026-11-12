# Opens a message in the reading pane. Free.
class ShiftAttempts::Messages::ReadingsController < ApplicationController
  include ShiftPlay
  include ShiftAttemptMessageScoped

  def create
    play { @attempt.read(@message) }
  end
end
