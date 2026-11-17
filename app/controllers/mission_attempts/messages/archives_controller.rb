# Archiving a message: the player is done with it.
class MissionAttempts::Messages::ArchivesController < ApplicationController
  include MissionPlay
  include MissionAttemptMessageScoped

  def create
    play { @attempt.archive(@message) }
  end
end
