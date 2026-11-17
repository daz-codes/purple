# Opening a downloaded file. If it was malware, nothing says so until the debrief.
class MissionAttempts::Tabs::DownloadRunsController < ApplicationController
  include MissionPlay

  def create
    play { @attempt.run_download }
  end
end
