# Opening a downloaded file that turns out to be malware.
class ShiftAttempts::Tabs::DownloadRunsController < ApplicationController
  include ShiftPlay

  def create
    play(alert: "Your files are being encrypted. IT has pulled your laptop off the network to stop it spreading. " \
                "Keep working from the spare machine.") do
      @attempt.run_download
    end
  end
end
