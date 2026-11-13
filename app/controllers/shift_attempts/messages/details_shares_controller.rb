# Sends details to a message from its "Send details" box: the ids of the chips picked. There's no text
# box, so nothing typed ever reaches the server.
class ShiftAttempts::Messages::DetailsSharesController < ApplicationController
  include ShiftPlay
  include ShiftAttemptMessageScoped

  def create
    play { @attempt.share_details(@message, Array(params[:chips])) }
  end
end
