# Lets time pass until the next message arrives.
class ShiftAttempts::WaitsController < ApplicationController
  include ShiftPlay

  def create
    play { @attempt.wait_for_mail }
  end
end
