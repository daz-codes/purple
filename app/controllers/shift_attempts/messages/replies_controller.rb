# Sends one of a text or chat's canned replies, by its neutral id. There's no free text.
class ShiftAttempts::Messages::RepliesController < ApplicationController
  include ShiftPlay
  include ShiftAttemptMessageScoped

  HANDED_OVER = "A minute later, someone signed in to your account from abroad. IT has locked it while they clean up. " \
                "Keep working, but whatever you sent them is theirs now.".freeze

  def create
    play(alert: -> { HANDED_OVER if @attempt.handed_over?(@message) }) do
      @attempt.send_reply(@message, params[:reply])
    end
  end
end
