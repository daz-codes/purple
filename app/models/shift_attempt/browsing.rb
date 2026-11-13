# The in-game browser. Clicking a link or opening an attachment opens it in a tab; the server
# decides which page appears there. Hovering to see the real URL is free and needs no move.
module ShiftAttempt::Browsing
  extend ActiveSupport::Concern

  TAB_OPENERS = %w[ click_link open_attachment ].freeze
  # Running a download closes the prompt. (Nothing visible happens: the damage shows in the debrief.)
  TAB_CLOSERS = %w[ close_landing run_download ].freeze
  # Pressing the button on a sign-in or portal page. The page stays open, showing a plain confirmation.
  TAB_SUBMITTERS = %w[ submit_credentials use_portal ].freeze

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
  # whose message has been dealt with, or whose link or attachment a content re-import removed, is
  # gone too, so nothing more can be done on it.
  def current_tab
    return @current_tab if defined?(@current_tab)

    index = actions.rindex { |action| action.kind.in?(TAB_OPENERS) || action.kind.in?(TAB_CLOSERS) }
    action = actions[index] if index
    message = arrived_messages.find { |arrived| arrived.key == action.target_key } if action&.kind.in?(TAB_OPENERS)
    if message && !handled?(message)
      submitted = actions.drop(index + 1).any? { |later| later.kind.in?(TAB_SUBMITTERS) }
      tab = ShiftAttempt::Tab.new(message:, source: action.result, submitted:)
    end
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
      reject "That's already been sent." if tab.submitted?
      tab
    end
end
