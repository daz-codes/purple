# Doing the task on a portal page, e.g. approving the invoice.
class ShiftAttempts::Tabs::TaskCompletionsController < ApplicationController
  include ShiftPlay

  def create
    play { @attempt.complete_task }
  end
end
