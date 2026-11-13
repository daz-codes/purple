# Falling for it: entering a password on a lookalike sign-in page, or running a file from a malware
# link or a disguised attachment. Nothing in the shift says so: the sign-in page carries on to a plain
# confirmation, as real phishing kits do, and a run file simply closes. The damage is revealed in the
# debrief.
#
# Mock sign-in pages never collect anything: the form's fields have no names, so nothing typed is
# ever sent. The server only records that the button was pressed.
module ShiftAttempt::Compromisable
  extend ActiveSupport::Concern

  COMPROMISING_KINDS = %w[ submit_credentials run_download ].freeze

  # details: chips picked for any other fields the page asks for (a memorable word, a staff number).
  def submit_credentials(details: [])
    acting_on do
      tab = current_tab_showing!("credential_harvest", "There's no sign-in page open.")
      share_on_page(tab, details)
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
