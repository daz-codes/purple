# Pressing the button on a portal page, e.g. approving the invoice, with any details picked for its
# fields (chip ids, never typed text).
class MissionAttempts::Tabs::PortalSubmissionsController < ApplicationController
  include MissionPlay

  def create
    play { @attempt.use_portal(details: Array(params[:details])) }
  end
end
