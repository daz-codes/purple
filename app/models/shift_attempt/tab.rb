# The page open in the in-game browser: a link the player clicked, or an attachment they opened.
# Built from the action that opened it, so it's never stored separately from the log.
#
# #landing picks the page the server renders. It reflects the hidden outcome, so it must only ever
# be used to render the page the player has already chosen to open, never anything else.
class ShiftAttempt::Tab
  # Pages where the player can fall for it. Opening one and backing out is a near miss.
  TRAP_LANDINGS = %w[ credential_harvest malware_download ].freeze

  attr_reader :message, :source

  # source: { "link" => "l1" } or { "attachment" => "a1" }, as recorded in the action's result.
  def initialize(message:, source:)
    @message = message
    @source = source
  end

  def link
    return @link if defined?(@link)

    @link = (message.links.find { |link| link.key == source["link"] } if source["link"])
  end

  def attachment
    message.attachment(source["attachment"])
  end

  def landing
    if link
      link.landing_template
    elsif attachment
      attachment["outcome"] == "malware" ? "malware_download" : "file_preview"
    end
  end

  # False once a content re-import has removed the link or attachment this tab was opened from.
  def showable?
    landing.present?
  end

  def trap?
    landing.in?(TRAP_LANDINGS)
  end

  def same_page?(other)
    other.present? && other.message == message && other.source == source
  end

  # What the address bar shows: where the link really goes. Attachments open locally, so they have none.
  def address
    link&.actual_url
  end

  def host
    URI(address).host if address
  end

  # Whether the address bar shows a padlock. It only means the connection is encrypted: phishing
  # sites have padlocks too.
  def padlock?
    address.to_s.start_with?("https://")
  end

  def title
    attachment ? attachment["name"] : host
  end

  # The file a download offers: the attachment's name, or the last part of the link's path.
  def file_name
    return attachment["name"] if attachment
    return unless address

    name = File.basename(URI(address).path.to_s)
    name.include?(".") ? name : "document.zip"
  end

  # The task a portal page completes.
  def task
    link&.task if landing == "portal_task"
  end
end
