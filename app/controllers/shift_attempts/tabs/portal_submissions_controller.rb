# Pressing the button on a portal page, e.g. approving the invoice.
class ShiftAttempts::Tabs::PortalSubmissionsController < ApplicationController
  include ShiftPlay

  def create
    play { @attempt.use_portal }
  end
end
