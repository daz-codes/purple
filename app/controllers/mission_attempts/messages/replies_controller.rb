# Sends one of a text or chat's canned replies, by its neutral id. There's no free text.
class MissionAttempts::Messages::RepliesController < ApplicationController
  include MissionPlay
  include MissionAttemptMessageScoped

  def create
    play { @attempt.send_reply(@message, params[:reply]) }
  end
end
