# A link inside a message. The browser only ever sees its key and URLs; the outcome and
# the task it completes stay on the server.
class Link < ApplicationRecord
  LANDING_TEMPLATES = %w[ portal_task harmless credential_harvest malware_download ].freeze

  enum :outcome, { completes_task: "completes_task", harmless: "harmless", bait_landing: "bait_landing", malware: "malware" },
    prefix: true, validate: true

  belongs_to :message
  belongs_to :task, optional: true

  validates :key, presence: true, uniqueness: { scope: :message_id }
  validates :display_url, :actual_url, presence: true
  validates :landing_template, inclusion: { in: LANDING_TEMPLATES }
  validates :task, presence: true, if: :outcome_completes_task?
  validates :task, absence: true, unless: :outcome_completes_task?
end
