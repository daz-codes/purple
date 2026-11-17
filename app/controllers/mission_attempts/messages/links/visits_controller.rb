# Clicking a link in a message opens it in the in-game browser. Only the link's neutral key is
# posted; the server decides which page appears.
class MissionAttempts::Messages::Links::VisitsController < ApplicationController
  include MissionPlay
  include MissionAttemptMessageScoped

  def create
    link = @message.links.find_by(key: params[:link_key]) or raise MissionAttempt::Rejected, "That link isn't in the message."

    play { @attempt.visit(link) }
  end
end
