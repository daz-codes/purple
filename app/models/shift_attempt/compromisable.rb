# Falling for it: entering a password on a lookalike sign-in page, or running a file from a malware
# link or a disguised attachment. The shift carries on, but the player sees the damage at once.
#
# Mock sign-in pages never collect anything: the form's fields have no names, so nothing typed is
# ever sent. The server only records that the button was pressed.
module ShiftAttempt::Compromisable
  extend ActiveSupport::Concern

  COMPROMISING_KINDS = %w[ submit_credentials run_download ].freeze

  def submit_credentials
    acting_on do
      tab = current_tab_showing!("credential_harvest", "There's no sign-in page open.")
      record :submit_credentials, message: tab.message, result: tab.source
    end
  end

  def run_download
    acting_on do
      tab = current_tab_showing!("malware_download", "There's no download open.")
      record :run_download, message: tab.message, result: tab.source
    end
  end
end
