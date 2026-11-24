# The file an intercept holds (a photo, a document), for the player to look at and the Workbench to read.
# Only the attempt's owner can fetch it. A photo is shown inline; anything else downloads.
class MissionAttempts::Intercepts::FilesController < ApplicationController
  # In this order: the attempt is found before its intercept.
  include MissionAttemptScoped
  include MissionAttemptInterceptScoped

  def show
    head :not_found and return unless @intercept.file?

    send_data @intercept.file_data, type: @intercept.file_type, filename: @intercept.file_name,
      disposition: @intercept.image? ? "inline" : "attachment"
  end
end
