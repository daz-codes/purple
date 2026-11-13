# Doing what a genuine message asks on the portal page its link opens: confirming the delivery slot,
# approving the invoice, or signing in with the details it asks for. The page then shows a plain "Submitted" confirmation, the same one a bait
# sign-in page shows, so neither says whether the player was right.
module ShiftAttempt::Portals
  extend ActiveSupport::Concern

  # details: chips picked for the page's fields, if it has any (see ShiftAttempt::Sharing).
  def use_portal(details: [])
    acting_on do
      tab = current_tab_showing!("portal", "There's nothing to do on this page.")
      share_on_page(tab, details)
      record :use_portal, message: tab.message, result: tab.source
    end
  end

  def used_portal?(message)
    done?(:use_portal, message.key)
  end
end
