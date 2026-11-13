module ShiftAttemptsHelper
  # A button for one move in a shift. The URL names the move and, for message moves, only the
  # message's opaque ref. Moves have no visible cost: time is never shown during a shift.
  def shift_action_button(label, path, params: {}, **options)
    button_to label, path, params:, class: options.fetch(:class, "btn-ghost"), form: { class: "contents" }
  end

  # The replies the player can still pick: "Why do you need this?" only until it's been asked.
  def reply_options(attempt, message)
    asked = attempt.asked_why?(message) && message.ask_why_reply
    message.visible_replies.reject { |option| asked && option["id"] == asked["id"] }
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
    "portal" => "shift_attempts/landings/portal",
    "credential_harvest" => "shift_attempts/landings/sign_in",
    "malware_download" => "shift_attempts/landings/download",
    "file_preview" => "shift_attempts/landings/document",
    "harmless" => "shift_attempts/landings/article"
  }.freeze

  # A submitted sign-in or portal page shows the same plain confirmation either way.
  def landing_partial(tab)
    tab.submitted? ? "shift_attempts/landings/submitted" : LANDING_PARTIALS.fetch(tab.landing)
  end

  HEADER_ANCHOR_LABELS = { "from" => "the sender", "reply_to" => "the Reply-To address", "to" => "the To address", "subject" => "the subject" }.freeze

  # How a flagged part of a message is named to the player: "the sender", the link's text, the
  # attachment's file name, or the highlighted words in quotes. Only ever what the player can see.
  def flag_label(message, flag)
    if flag.text?
      words = message.paragraphs[flag.anchor]&.excerpt(flag.from, flag.to)
      return words ? "“#{words.truncate(60)}”" : "some text"
    end

    HEADER_ANCHOR_LABELS[flag.anchor] ||
      case flag.anchor
      when /\Al\d+\z/ then "the link “#{message.link(flag.anchor)&.display_url || "that was here"}”"
      else message.attachment(flag.anchor)&.fetch("name") || "a part that's no longer there"
      end
  end

  # The player's own flags, for the flag-mode controller to draw: whole parts by anchor, and text as
  # ranges. Never anything about red flags.
  def flags_json(flags)
    flags.map(&:to_result).to_json
  end

  # The player's notes on a message, as highlight ranges only: never whether they match a detail.
  def notes_json(notes)
    notes.map { |note| { anchor: note.anchor, from: note.from, to: note.to } }.to_json
  end
end
