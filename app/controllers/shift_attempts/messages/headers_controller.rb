# Shows the full headers behind the display name.
class ShiftAttempts::Messages::HeadersController < ApplicationController
  include ShiftPlay
  include ShiftAttemptMessageScoped

  def create
    play { @attempt.expand_headers(@message) }
  end
end
