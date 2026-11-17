# Shows the full headers behind the display name.
class MissionAttempts::Messages::HeadersController < ApplicationController
  include MissionPlay
  include MissionAttemptMessageScoped

  def create
    play { @attempt.expand_headers(@message) }
  end
end
