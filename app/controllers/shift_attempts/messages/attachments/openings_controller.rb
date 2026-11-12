# Opening an attachment: a document preview, or the prompt a program shows before it runs.
class ShiftAttempts::Messages::Attachments::OpeningsController < ApplicationController
  include ShiftPlay
  include ShiftAttemptMessageScoped

  def create
    play { @attempt.open_attachment(@message, params[:attachment_key]) }
  end
end
