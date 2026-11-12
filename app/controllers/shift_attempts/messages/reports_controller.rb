# Reports a message as phishing.
class ShiftAttempts::Messages::ReportsController < ApplicationController
  include ShiftPlay
  include ShiftAttemptMessageScoped

  def create
    play { @attempt.report(@message) }
  end
end
