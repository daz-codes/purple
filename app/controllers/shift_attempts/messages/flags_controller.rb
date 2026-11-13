# Flags (or unflags) part of a message: a whole part or sentence by its neutral anchor, or a
# highlighted range (from, to) of a paragraph's text. The reader comes back still in flag mode, so the
# player can carry on flagging.
class ShiftAttempts::Messages::FlagsController < ApplicationController
  include ShiftPlay
  include ShiftAttemptMessageScoped

  def create
    @flag_mode = true
    play { @attempt.flag(@message, params[:anchor], from: params[:from].presence, to: params[:to].presence) }
  end
end
