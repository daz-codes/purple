# Opening an attachment: a document preview, or the prompt a program shows before it runs.
class MissionAttempts::Messages::Attachments::OpeningsController < ApplicationController
  include MissionPlay
  include MissionAttemptMessageScoped

  def create
    play { @attempt.open_attachment(@message, params[:attachment_key]) }
  end
end
