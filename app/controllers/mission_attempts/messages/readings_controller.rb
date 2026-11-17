# Opens a message in the reading pane. Free.
class MissionAttempts::Messages::ReadingsController < ApplicationController
  include MissionPlay
  include MissionAttemptMessageScoped

  def create
    play { @attempt.read(@message) }
  end
end
