module ShiftAttemptsHelper
  # A button for one move in a shift, labelled with what it costs and disabled when it won't fit in
  # the time left. The URL names the move and, for message moves, only the message's opaque ref.
  def shift_action_button(attempt, label, path, cost: 0, params: {}, **options)
    button_to cost.positive? ? "#{label} (#{cost} min)" : label, path,
      params:,
      disabled: !attempt.affordable?(cost),
      class: options.fetch(:class, "btn-ghost"),
      form: { class: "contents" }
  end

  # The partials for the list of messages and the open message: an email client for an inbox shift,
  # a phone for a message shift. Their outer ids are the same, so every move's Turbo Stream works for both.
  PANE_PARTIALS = {
    "inbox" => { inbox: "shift_attempts/inbox", reader: "shift_attempts/reader" },
    "messages" => { inbox: "shift_attempts/phone/conversations", reader: "shift_attempts/phone/thread" }
  }.freeze

  def pane_partial(attempt, pane)
    PANE_PARTIALS.fetch(attempt.shift.kind).fetch(pane)
  end

  # Each channel's name: the label a phone app shows, and the noun for it in a sentence. Chats come
  # through the company's work chat app.
  CHANNEL_NAMES = {
    "email" => { label: "Email", noun: "email" },
    "sms" => { label: "Text message", noun: "text" },
    "chat" => { label: "Workchat", noun: "chat message" }
  }.freeze

  def channel_label(message)
    CHANNEL_NAMES.fetch(message.channel).fetch(:label)
  end

  # The letter on a conversation's avatar: the sender's initial, or # for a bare number.
  def avatar_initial(message)
    initial = message.from_name.strip[0]
    initial.match?(/[[:alpha:]]/) ? initial.upcase : "#"
  end

  # The page each landing shows in the in-game browser. Partial names are neutral ("sign_in", not
  # "credential_harvest") because they can surface in error pages and logs.
  LANDING_PARTIALS = {
    "portal_task" => "shift_attempts/landings/portal",
    "credential_harvest" => "shift_attempts/landings/sign_in",
    "malware_download" => "shift_attempts/landings/download",
    "file_preview" => "shift_attempts/landings/document",
    "harmless" => "shift_attempts/landings/article"
  }.freeze

  def landing_partial(tab)
    LANDING_PARTIALS.fetch(tab.landing)
  end

  HEADER_ANCHOR_LABELS = { "from" => "the sender", "reply_to" => "the Reply-To address", "to" => "the To address", "subject" => "the subject" }.freeze

  # How a flagged part of a message is named to the player: "the sender", "paragraph 2", the link's
  # text, or the attachment's file name. Only ever what the player can see in the message.
  def anchor_label(message, anchor)
    HEADER_ANCHOR_LABELS[anchor] ||
      case anchor
      when /\Ap(\d+)\z/ then "paragraph #{$1}"
      when /\Al(\d+)\z/ then "the link “#{message.links.find { |link| link.key == anchor }&.display_url || "link #{$1}"}”"
      else message.attachment(anchor)&.fetch("name") || anchor
      end
  end

  def shift_clock_label(attempt)
    "Minute #{attempt.clock_minutes} of #{attempt.time_budget}"
  end

  def task_state(attempt, task)
    if attempt.task_completed?(task) then :done
    elsif attempt.task_overdue?(task) then :overdue
    else :pending
    end
  end
end
