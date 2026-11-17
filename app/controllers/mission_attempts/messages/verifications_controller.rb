# Calls the sender back on a number the player already holds.
class MissionAttempts::Messages::VerificationsController < ApplicationController
  include MissionPlay
  include MissionAttemptMessageScoped

  def create
    play { @attempt.verify_sender(@message) }
  end
end
