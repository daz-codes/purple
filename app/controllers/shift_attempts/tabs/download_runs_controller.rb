# Opening a downloaded file. If it was malware, nothing says so until the debrief.
class ShiftAttempts::Tabs::DownloadRunsController < ApplicationController
  include ShiftPlay

  def create
    play { @attempt.run_download }
  end
end
