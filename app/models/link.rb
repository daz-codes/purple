# A link inside a message. The browser only ever sees its key and URLs; the outcome stays on the
# server. A portal link opens the page where the player does what a genuine message asks, by pressing
# its portal_action ("Confirm the delivery slot").
class Link < ApplicationRecord
  LANDING_TEMPLATES = %w[ portal harmless credential_harvest malware_download ].freeze

  enum :outcome, { portal: "portal", harmless: "harmless", bait_landing: "bait_landing", malware: "malware" },
    prefix: true, validate: true

  belongs_to :message

  validates :key, presence: true, uniqueness: { scope: :message_id }
  validates :display_url, :actual_url, presence: true
  validates :landing_template, inclusion: { in: LANDING_TEMPLATES }
  validates :portal_action, presence: true, if: :outcome_portal?
  validates :portal_action, absence: true, unless: :outcome_portal?
end
