# Flags (or unflags) one part of a message, by its neutral anchor. The reader comes back still in
# flag mode, so the player can carry on flagging.
class ShiftAttempts::Messages::FlagsController < ApplicationController
  include ShiftPlay
  include ShiftAttemptMessageScoped

  def create
    @flag_mode = true
    play { @attempt.flag(@message, params[:anchor]) }
  end
end
