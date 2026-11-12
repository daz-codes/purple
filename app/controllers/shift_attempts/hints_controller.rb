# Reveals the shift's next hint.
class ShiftAttempts::HintsController < ApplicationController
  include ShiftPlay

  def create
    play { @attempt.use_hint }
  end
end
