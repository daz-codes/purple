# Calls the sender back on a number the player already holds.
class ShiftAttempts::Messages::VerificationsController < ApplicationController
  include ShiftPlay
  include ShiftAttemptMessageScoped

  def create
    play { @attempt.verify_sender(@message) }
  end
end
