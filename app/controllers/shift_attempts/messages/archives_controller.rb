# Archiving a message: the player is done with it.
class ShiftAttempts::Messages::ArchivesController < ApplicationController
  include ShiftPlay
  include ShiftAttemptMessageScoped

  def create
    play { @attempt.archive(@message) }
  end
end
