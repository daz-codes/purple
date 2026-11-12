# The in-game browser. Clicking a link or opening an attachment opens it in a tab; the server
# decides which page appears there. Hovering to see the real URL is free and needs no move.
module ShiftAttempt::Browsing
  extend ActiveSupport::Concern

  TAB_OPENERS = %w[ click_link open_attachment ].freeze
  # Signing in or running a download ends with the page closing as the consequence lands.
  TAB_CLOSERS = %w[ close_landing submit_credentials run_download ].freeze

  def visit(link)
    acting_on(link.message) { open_tab :click_link, link.message, "link" => link.key }
  end

  def open_attachment(message, attachment_id)
    acting_on(message) do
      attachment = message.attachment(attachment_id) or reject "That attachment isn't there."

      open_tab :open_attachment, message, "attachment" => attachment["id"]
    end
  end

  def close_tab
    acting_on do
      tab = current_tab or reject "There's no page open."

      record :close_landing, message: tab.message, result: tab.source
    end
  end

  # The open tab, if any: the last link or attachment opened, unless it's been closed since. A tab
  # whose message has been reported, or whose link or attachment a content re-import removed, is
  # gone too, so nothing more can be done on it.
  def current_tab
    return @current_tab if defined?(@current_tab)

    action = actions.reverse_each.find { |action| action.kind.in?(TAB_OPENERS) || action.kind.in?(TAB_CLOSERS) }
    message = arrived_messages.find { |arrived| arrived.key == action.target_key } if action&.kind.in?(TAB_OPENERS)
    tab = ShiftAttempt::Tab.new(message:, source: action.result) if message && !reported?(message)
    @current_tab = (tab if tab&.showable?)
  end

  def reload(*)
    remove_instance_variable(:@current_tab) if defined?(@current_tab)
    super
  end

  private
    # A second click on the page already open (a double-click, or a held Enter) changes nothing.
    def open_tab(kind, message, source)
      reject "That's already open." if ShiftAttempt::Tab.new(message:, source:).same_page?(current_tab)

      record kind, message:, result: source
    end

    def current_tab_showing!(landing, otherwise)
      tab = current_tab
      reject otherwise unless tab&.landing == landing
      tab
    end
end
