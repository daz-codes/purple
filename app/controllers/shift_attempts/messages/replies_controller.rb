# Sends one of a text or chat's canned replies, by its neutral id. There's no free text.
class ShiftAttempts::Messages::RepliesController < ApplicationController
  include ShiftPlay
  include ShiftAttemptMessageScoped

  def create
    play { @attempt.send_reply(@message, params[:reply]) }
  end
end
