# The words of the Purple debrief: what each message was, what it needed, what the player did, and
# what to do next time. Everything here is judged by ShiftAttempt::Scorecard, so the explanation
# always matches the score. Only ever rendered for a finished attempt: it names the answers.
module DebriefsHelper
  TONE_CLASSES = {
    good: "border-safe/60 bg-safe-soft text-safe",
    warn: "border-warn/60 bg-warn-soft text-warn",
    bad: "border-red-team/60 bg-red-team-soft text-red-team",
    neutral: "border-line bg-surface-sunken text-ink-muted"
  }.freeze

  PHISH_VERDICTS = {
    compromised: [ "Phish: you fell for it", :bad ],
    reported: [ "Phish: reported", :good ],
    near_miss: [ "Phish: close call", :warn ],
    not_reported: [ "Phish: not reported", :warn ],
    never_arrived: [ "Phish: still to come when you stopped", :neutral ]
  }.freeze

  GENUINE_VERDICTS = {
    reported_wrongly: [ "Genuine: reported by mistake", :bad ],
    done: [ "Genuine: dealt with", :good ],
    done_late: [ "Genuine: dealt with, but late", :warn ],
    not_done: [ "Genuine: not dealt with", :bad ],
    never_arrived: [ "Genuine: still to come when you stopped", :warn ]
  }.freeze

  # How each kind of mark looks on the debrief's copy of a message.
  MARK_CLASSES = {
    hit: "bg-safe-soft", wrong: "bg-warn-soft",
    found: "underline decoration-2 decoration-safe", missed: "underline decoration-2 decoration-red-team"
  }.freeze

  def debrief_tone_classes(tone)
    TONE_CLASSES.fetch(tone)
  end

  def debrief_text_class(tone)
    TONE_CLASSES.fetch(tone).split.last unless tone == :neutral
  end

  # [label, tone]
  def debrief_verdict(result)
    (result.phish? ? PHISH_VERDICTS : GENUINE_VERDICTS).fetch(result.outcome)
  end

  def debrief_points(points)
    if points.positive? then "+#{points}"
    elsif points.negative? then "−#{points.abs}"
    else "0"
    end
  end

  def debrief_stars(count)
    tag.span("★" * count + "☆" * (3 - count), class: "tracking-widest text-purple-team",
      aria: { label: "#{count} of 3 stars" }, data: { testid: "stars" })
  end

  # "7 min 05 s"
  def debrief_duration(seconds)
    minutes, seconds = seconds.divmod(60)
    minutes.zero? ? "#{seconds} s" : format("%d min %02d s", minutes, seconds)
  end

  # "4:05" into the shift.
  def debrief_clock(seconds)
    format("%d:%02d", *seconds.divmod(60))
  end

  # A finished attempt's status, for the track page.
  def debrief_status(attempt)
    { "completed" => "Completed", "clocked_off" => "Clocked off early", "timed_out" => "Left unfinished" }.fetch(attempt.status, "In progress")
  end

  # How the shift ended, and how long it took.
  def debrief_ending(attempt, scorecard)
    case attempt.status
    when "completed"
      time = "You cleared your #{attempt.shift.kind_inbox? ? "inbox" : "phone"} in #{debrief_duration(scorecard.elapsed_seconds)}"
      if scorecard.relaxed?
        "#{time}, in relaxed mode."
      else
        "#{time}. The target was #{attempt.shift.par_minutes} minutes."
      end
    when "clocked_off"
      "You clocked off after #{debrief_duration(scorecard.elapsed_seconds)}. Anything you hadn't dealt with counts as ignored."
    else
      "This shift was left open too long and closed. Anything you hadn't dealt with counts as ignored."
    end
  end

  def debrief_headline(scorecard)
    return "A perfect shift: every message handled right, every red flag spotted, with no wrong flags and no hints." if scorecard.perfect?

    phishes = scorecard.phishes
    genuine = scorecard.genuine
    parts = []
    parts << "reported #{phishes.count(&:reported?)} of #{pluralize(phishes.size, "phish")}" if phishes.any?
    compromised = phishes.count(&:compromised?)
    parts << "fell for #{compromised}" if compromised.positive?
    parts << "dealt with #{genuine.count(&:done?)} of #{pluralize(genuine.size, "genuine message")}" if genuine.any?
    red_flags = phishes.sum { |result| result.message.red_flags.size }
    parts << "spotted #{phishes.sum { |result| result.found_flags.size }} of #{pluralize(red_flags, "red flag")}" if red_flags.positive?
    wrong_flags = scorecard.messages.sum { |result| result.false_flags.size }
    parts << "flagged #{pluralize(wrong_flags, "thing")} that #{wrong_flags == 1 ? "wasn't a red flag" : "weren't red flags"}" if wrong_flags.positive?
    parts << "took #{pluralize(scorecard.hints.size, "hint")}" if scorecard.hints.any?
    parts.any? ? "You #{parts.to_sentence}." : "Shift over."
  end

  # What a genuine message needed, as the end of a sentence: "needed a reply".
  def debrief_need(message)
    case message.expects
    when "reply" then "needed a reply"
    when "act" then "needed you to #{portal_action_phrase(message)}"
    else "needed nothing more than reading and archiving"
    end
  end

  # What happened, in plain words, one sentence per paragraph.
  def debrief_story(result)
    message = result.message
    story = []

    if !result.arrived?
      story << "This was still on its way when you stopped."
      story << (result.phish? ? "It was a phish, so no harm done, but nobody reported it." :
        "It was genuine, and #{debrief_need(message)} (#{debrief_points(result.handling_points)}).")
    elsif result.phish?
      story << reply_sentence(result) if result.reply
      result.compromises.each { |tab| story << compromise_sentence(tab) }
      result.near_misses.each { |tab| story << near_miss_sentence(tab) }

      if result.reported?
        story << if result.compromised?
          "You reported it afterwards, which is exactly right once you realise: the sooner security knows, the less damage is done."
        elsif result.near_miss?
          "You then reported it. Good call."
        else
          "This was a phish and you reported it. Well done: the security team can now warn everyone else."
        end
      else
        story << "#{result.archived? ? "You archived it without reporting it" : "You didn't report it"}. Reporting a phish lets the " \
          "security team warn your colleagues before it catches one of them (#{debrief_points(ShiftAttempt::Scorecard::REPORTED_PHISH)} you could have had)."
      end
    else
      story.concat(genuine_story(result))
    end

    story
  end

  # The habit to take away, if the player was caught out or came close.
  def debrief_lessons(result)
    tabs = result.compromises + result.near_misses
    lessons = tabs.map(&:landing).uniq.filter_map do |landing|
      case landing
      when "credential_harvest"
        "Don't sign in from a link in a message. Go to the site you already know, by bookmark or by typing its address, " \
          "and check the address bar before you type a password. A padlock only means the connection is encrypted, not that the site is genuine."
      when "malware_download"
        "Don't open files you weren't expecting, and read the whole file name: one that ends in .exe is a program, whatever it says before that."
      end
    end
    if result.gave_in?
      lessons << "Never share a one-time code, a password or an approval with anyone who asks for it, whoever they say they are. " \
        "IT will never ask: the code exists to prove it's you."
    end
    lessons << "When a request is unexpected, check with the sender on a number you already hold before acting on it." if result.reported? && !result.phish?
    lessons
  end

  # What the sender said, or would have said, when called back.
  def debrief_verification(result)
    reply = result.message.verify_result.presence or return

    if result.checked_first?
      "You checked with someone you already trust: “#{result.reply["check"]}”"
    elsif result.verified?
      "You called the sender back: “#{reply}”"
    elsif result.outcome.in?(%i[ compromised near_miss not_reported reported_wrongly ])
      "Calling the sender back would have told you: “#{reply}”"
    end
  end

  # [seconds into the shift, description, tone] for each action in the shift's log, in order.
  def debrief_timeline(actions, scorecard)
    actions.zip(ShiftAttempt::Flaggable.toggles(actions)).map do |action, on|
      debrief_timeline_entry(action, scorecard, unflag: on == false)
    end
  end

  # [seconds into the shift, description, tone] for one action in the shift's log. unflag: the
  # flag_element took a flag off rather than putting one on.
  def debrief_timeline_entry(action, scorecard, unflag: false)
    result = scorecard.message_result_for(action.target_key)
    subject = result ? "“#{result.message.subject.presence || result.message.from_name}”" : "a message"
    tab = ShiftAttempt::Tab.new(message: result.message, source: action.result) if result

    description, tone =
      case action.kind
      when "open_message" then [ "Opened #{subject}", :neutral ]
      when "expand_headers" then [ "Checked the full headers of #{subject}", :neutral ]
      when "verify_sender" then [ "Called the sender of #{subject} back (+#{action.penalty_seconds} s)", :neutral ]
      when "click_link" then [ "Clicked the link to #{tab_label(tab)} in #{subject}", tab&.trap? ? :warn : :neutral ]
      when "open_attachment" then [ "Opened the attachment #{tab_label(tab)} from #{subject}", tab&.trap? ? :warn : :neutral ]
      when "close_landing" then [ "Closed #{tab_label(tab)}", tab&.trap? ? :good : :neutral ]
      when "submit_credentials" then [ "Entered a password on #{tab_label(tab)}: compromised", :bad ]
      when "run_download" then [ "Ran #{tab_label(tab)}: compromised", :bad ]
      when "use_portal" then [ "Pressed “#{tab&.portal_action || "the button"}” on #{tab_label(tab)}", :good ]
      when "flag_element"
        part = result ? flag_label(result.message, ShiftAttempt::Flag.from_result(action.result)) : "part of it"
        [ "#{unflag ? "Took the flag off" : "Flagged"} #{part} in #{subject}", :neutral ]
      when "send_reply"
        reply = action.result
        tone = { "compromise" => :bad, "verify" => :good, "poor" => :warn }.fetch(reply["outcome"], :neutral)
        [ "Replied “#{reply["text"]}” to #{subject}#{", and checked with someone you trust" if reply["check"]}", tone ]
      when "use_hint" then [ "Took a hint", :warn ]
      when "report_message" then [ "Reported #{subject}", result.nil? ? :neutral : (result.phish? ? :good : :bad) ]
      when "archive_message" then [ "Archived #{subject}", result.nil? || result.phish? || result.done? ? :neutral : :warn ]
      when "clock_off" then [ "Clocked off early", :neutral ]
      else [ action.kind.humanize, :neutral ]
      end

    [ action.at_seconds, description, tone ]
  end

  # Where the answer to a question was, for a message that asked one: "It was in HR's email: “Room 4B”".
  def debrief_answer_source(result)
    source = result.message.answer_source or return
    where = "#{source.from_name}'s #{message_noun(source)}"

    if result.replied_well?
      "You'd read carefully: the answer was in #{where}: “#{result.message.answer_in_quote}”."
    else
      "The answer was in #{where}: “#{result.message.answer_in_quote}”. Messages often hold details you'll need later."
    end
  end

  # What an earlier, genuine message said that a red flag contradicts: "Earlier, Larkhill IT told you: “…”".
  def debrief_contradiction(red_flag)
    source = red_flag.contradicted_message or return
    "Earlier, #{source.from_name} told you: “#{red_flag.contradicts_quote}”"
  end

  # Each red flag in a phish, and whether the player found it: [red_flag, found?].
  def debrief_red_flags(result)
    found = result.found_flags
    result.message.red_flags.map { |red_flag| [ red_flag, found.include?(red_flag) ] }
  end

  # The things the player flagged that weren't giveaways.
  def debrief_false_flags(result)
    return if result.false_flags.empty?

    parts = result.false_flags.map { |flag| flag_label(result.message, flag) }.to_sentence
    cost = debrief_points(result.false_flags.size * ShiftAttempt::Scorecard::FALSE_FLAG)
    if result.phish?
      "You also flagged #{parts}, which #{result.false_flags.one? ? "wasn't a giveaway" : "weren't giveaways"} (#{cost})."
    else
      "You flagged #{parts}, but this #{message_noun(result.message)} was genuine (#{cost})."
    end
  end

  # The message's text with the player's highlights and the quoted red flags marked on it, one
  # paragraph at a time: [[text, classes], …] per paragraph. Only for messages where there's something
  # to show.
  def debrief_marked_paragraphs(result)
    text_flags = result.flags.select(&:text?)
    quotes = result.message.red_flags.select(&:quote?)
    return [] if text_flags.empty? && quotes.empty?

    found = result.found_flags
    result.message.paragraphs.values.map do |paragraph|
      highlights = text_flags.select { |flag| flag.anchor == paragraph.anchor }
      red = quotes.select { |quote| quote.anchor == paragraph.anchor }
      marks = highlights.map { |flag| [ flag.from, flag.to, result.message.red_flags.any? { |red_flag| red_flag.found_by?(flag) } ? :hit : :wrong ] } +
        red.map { |quote| [ quote.quote_start, quote.quote_end, found.include?(quote) ? :found : :missed ] }

      cuts = ([ 0, paragraph.text.length ] + marks.flat_map { |from, to, _| [ from, to ] }).uniq.sort
      cuts.each_cons(2).filter_map do |from, to|
        kinds = marks.select { |mark_from, mark_to, _| mark_from <= from && to <= mark_to }.map(&:last)
        [ paragraph.text[from...to], mark_classes(kinds) ] if to > from
      end
    end
  end

  # What to call a message in a sentence: an email, a text or a chat message.
  def message_noun(message)
    ShiftAttemptsHelper::CHANNEL_NAMES.fetch(message.channel).fetch(:noun)
  end

  private
    # A <mark> has the browser's yellow background unless it's one of the player's highlights.
    def mark_classes(kinds)
      return if kinds.empty?

      classes = kinds.map { |kind| MARK_CLASSES.fetch(kind) }
      classes << "bg-transparent" unless kinds.intersect?(%i[ hit wrong ])
      classes.uniq.join(" ")
    end

    def genuine_story(result)
      message = result.message
      need = debrief_need(message)
      noun = message_noun(message)

      if result.reported?
        [ "This was genuine, and #{need}, but you reported it. False alarms cost the security team time." ]
      elsif result.done?
        story = [ "This was genuine and #{need}. #{done_sentence(result)}" ]
        if result.late?
          story << "It was urgent: it needed dealing with within #{pluralize(message.urgent_within_minutes, "minute")} of arriving, " \
            "and you took #{debrief_duration(result.done_at_seconds - result.arrived_at)}, so it earns half."
        end
        story << "Trusting the real #{noun} matters as much as spotting the fake one." if message.expects_act?
        story
      elsif result.handling_points.zero?
        [ "This was genuine and #{need}. It was still in your #{result.message.email? ? "inbox" : "messages"} when you stopped, " \
          "which costs nothing for a message like this." ]
      else
        [ "This was genuine and #{need}, but #{not_done_reason(result)} (#{debrief_points(result.handling_points)})." ]
      end
    end

    def done_sentence(result)
      case result.message.expects
      when "reply" then "You replied “#{result.reply["text"]}”."
      when "act" then "You did it, through its link."
      else "You archived it."
      end
    end

    def not_done_reason(result)
      if result.reply.present? && result.message.expects_reply?
        "your reply, “#{result.reply["text"]}”, didn't do what it asked"
      elsif result.archived?
        "you archived it without doing that"
      else
        "it was still in your #{result.message.email? ? "inbox" : "messages"} when you stopped"
      end
    end

    def portal_action_phrase(message)
      action = message.links.find(&:outcome_portal?)&.portal_action
      action ? "“#{action}” through its link" : "use its link"
    end

    def reply_sentence(result)
      text = result.reply["text"]
      if result.gave_in?
        "You replied “#{text}”, handing over exactly what they asked for. In a real attack Red is now signed in as you " \
          "(#{debrief_points(ShiftAttempt::Scorecard::COMPROMISED)})."
      else
        "You replied “#{text}”, and gave them nothing they could use. Good."
      end
    end

    def compromise_sentence(tab)
      if !tab.showable?
        "You were compromised by a link or file in this message that has since been changed in the shift's content."
      elsif tab.landing == "credential_harvest"
        "You entered a password on the fake sign-in page at #{tab.host}. It just said “submitted”, but in a real attack Red now " \
          "has your password: they could read your email and send phish to your colleagues from your account."
      elsif tab.attachment
        "You opened #{tab.file_name}. Nothing seemed to happen, but it wasn't a document: it was a program in disguise, and it started encrypting your files."
      else
        "You ran #{tab.file_name}, downloaded from #{tab.host}. Nothing seemed to happen, but it was malware, and it started encrypting your files."
      end
    end

    def near_miss_sentence(tab)
      if tab.landing == "credential_harvest"
        "You opened the fake sign-in page at #{tab.host}, but closed it without signing in. A close call: " \
          "spot it before you click next time, because some pages can do harm just by being visited."
      elsif tab.attachment
        "You tried to open #{tab.file_name}, but cancelled when asked to run it. A close call: the .exe at the end was the giveaway."
      else
        "You started downloading #{tab.file_name} from #{tab.host}, but cancelled it. A close call."
      end
    end

    def tab_label(tab)
      return "a page" unless tab
      tab.attachment ? tab.file_name : (tab.host || "a page")
    end
end
