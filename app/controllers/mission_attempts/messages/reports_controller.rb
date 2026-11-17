# Reports a message as phishing.
class MissionAttempts::Messages::ReportsController < ApplicationController
  include MissionPlay
  include MissionAttemptMessageScoped

  def create
    play { @attempt.report(@message) }
  end
end
