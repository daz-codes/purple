# The words of the Purple debrief: what happened with each message, why, and what to do next time.
# Everything here is judged by ShiftAttempt::Scorecard, so the explanation always matches the score.
# Only ever rendered for a finished attempt: it names the answers.
module DebriefsHelper
  TONE_CLASSES = {
    good: "border-safe/60 bg-safe-soft text-safe",
    warn: "border-warn/60 bg-warn-soft text-warn",
    bad: "border-red-team/60 bg-red-team-soft text-red-team",
    neutral: "border-line bg-surface-sunken text-ink-muted"
  }.freeze

  VERDICTS = {
    compromised: [ "Phish: you fell for it", :bad ],
    reported: [ "Phish: reported", :good ],
    near_miss: [ "Phish: close call", :warn ],
    not_reported: [ "Phish: not reported", :warn ],
    arrived_after_shift: [ "Phish: arrived after you left", :warn ],
    reported_wrongly: [ "Genuine: reported by mistake", :bad ],
    used: [ "Genuine: used for your work", :good ],
    left_alone: [ "Genuine", :neutral ]
  }.freeze

  def debrief_tone_classes(tone)
    TONE_CLASSES.fetch(tone)
  end

  def debrief_text_class(tone)
    TONE_CLASSES.fetch(tone).split.last unless tone == :neutral
  end

  # [label, tone]
  def debrief_verdict(result)
    VERDICTS.fetch(result.outcome)
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

  def debrief_headline(scorecard)
    phishes = scorecard.phishes
    reported = phishes.count(&:reported?)
    compromised = phishes.count(&:compromised?)

    if scorecard.perfect?
      "A perfect shift: every task done on time, every phish reported and every red flag spotted, with no wrong flags and no hints."
    else
      parts = []
      parts << "reported #{reported} of #{pluralize(phishes.size, "phish")}" if phishes.any?
      parts << "fell for #{compromised}" if compromised.positive?
      red_flags = phishes.sum { |result| result.message.red_flags.size }
      parts << "spotted #{phishes.sum { |result| result.found_flags.size }} of #{pluralize(red_flags, "red flag")}" if red_flags.positive?
      wrong_flags = scorecard.messages.sum { |result| result.false_flags.size }
      parts << "flagged #{pluralize(wrong_flags, "part")} that #{wrong_flags == 1 ? "wasn't a red flag" : "weren't red flags"}" if wrong_flags.positive?
      tasks = scorecard.tasks
      parts << "finished #{tasks.count(&:on_time?)} of #{pluralize(tasks.size, "task")} on time" if tasks.any?
      parts << "took #{pluralize(scorecard.hints.size, "hint")}" if scorecard.hints.any?
      parts.any? ? "You #{parts.to_sentence}." : "Shift over."
    end
  end

  # What happened, in plain words, one sentence per paragraph.
  def debrief_story(result)
    message = result.message
    story = []

    if !result.arrived?
      story << "This arrived at minute #{message.arrives_at_minute}, after you'd ended your shift."
      if result.phish?
        story << "It was a phish, and nobody was there to report it. Stay until the day's mail is in: " \
          "reporting it would have been worth #{debrief_points(ShiftAttempt::Scorecard::REPORTED_PHISH)}."
      else
        tasks = message.links.select(&:outcome_completes_task?).map(&:task).uniq
        story << (tasks.any? ? "It was genuine, and the way to #{quoted_titles(tasks)}." : "It was genuine.")
      end
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
      elsif result.opened? || result.near_miss?
        story << "You didn't report it. Reporting a phish lets the security team warn your colleagues before it catches one of them " \
          "(#{debrief_points(ShiftAttempt::Scorecard::REPORTED_PHISH)} you could have had)."
      else
        story << "You never opened it, so it couldn't hurt you, but it's still sitting in everyone else's inbox. " \
          "Reporting a phish lets the security team warn your colleagues " \
          "(#{debrief_points(ShiftAttempt::Scorecard::REPORTED_PHISH)} you could have had)."
      end
    else
      tasks = message.links.select(&:outcome_completes_task?).map(&:task).uniq
      if result.reported?
        sentence = "This was genuine, but you reported it. False alarms cost the security team time"
        sentence += tasks.any? ? ", and it was the #{message_noun(message)} you needed for #{quoted_titles(tasks)}." : "."
        story << sentence
      elsif result.completed_tasks.any?
        story << "This was genuine, and you used it for #{quoted_titles(result.completed_tasks)}. " \
          "Trusting the real #{message_noun(message)} matters as much as spotting the fake one."
      elsif tasks.any?
        story << "This was genuine, and it was the way to #{quoted_titles(tasks)}, which you didn't finish."
      else
        story << "This was genuine. Nothing to do here, and nothing went wrong."
      end
    end

    story
  end

  # The habit to take away, if the player was caught out or came close.
  def debrief_lessons(result)
    tabs = result.compromises + result.near_misses
    lessons = tabs.map(&:landing).uniq.filter_map do |landing|
      case landing
      when "credential_harvest"
        "Don't sign in from a link in an email. Go to the site you already know, by bookmark or by typing its address, " \
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

  # [minute, description, tone] for each action in the shift's log, in order.
  def debrief_timeline(actions, scorecard)
    actions.zip(ShiftAttempt::Flaggable.toggles(actions)).map do |action, on|
      debrief_timeline_entry(action, scorecard, unflag: on == false)
    end
  end

  # [minute, description, tone] for one action in the shift's log. unflag: the flag_element took a
  # flag off rather than putting one on.
  def debrief_timeline_entry(action, scorecard, unflag: false)
    result = scorecard.message_result_for(action.target_key)
    subject = result ? "“#{result.message.subject.presence || result.message.from_name}”" : "a message"
    tab = ShiftAttempt::Tab.new(message: result.message, source: action.result) if result

    description, tone =
      case action.kind
      when "open_message" then [ "Opened #{subject}", :neutral ]
      when "expand_headers" then [ "Checked the full headers of #{subject}", :neutral ]
      when "verify_sender" then [ "Called the sender of #{subject} back", :neutral ]
      when "hover_link" then [ "Checked where a link in #{subject} goes", :neutral ]
      when "click_link" then [ "Clicked the link to #{tab_label(tab)} in #{subject}", tab&.trap? ? :warn : :neutral ]
      when "open_attachment" then [ "Opened the attachment #{tab_label(tab)} from #{subject}", tab&.trap? ? :warn : :neutral ]
      when "close_landing" then [ "Closed #{tab_label(tab)}", tab&.trap? ? :good : :neutral ]
      when "submit_credentials" then [ "Entered a password on #{tab_label(tab)}: compromised", :bad ]
      when "run_download" then [ "Ran #{tab_label(tab)}: compromised", :bad ]
      when "flag_element"
        part = result ? anchor_label(result.message, action.result["anchor"]) : "part"
        [ "#{unflag ? "Took the flag off" : "Flagged"} #{part} in #{subject}", :neutral ]
      when "send_reply"
        reply = action.result
        tone = { "compromise" => :bad, "verify" => :good }.fetch(reply["outcome"], :neutral)
        [ "Replied “#{reply["text"]}” to #{subject}#{", and checked with someone you trust" if reply["check"]}", tone ]
      when "use_hint" then [ "Took a hint", :warn ]
      when "report_message" then [ "Reported #{subject}", result.nil? ? :neutral : (result.phish? ? :good : :bad) ]
      when "complete_task" then [ "Completed “#{task_title(scorecard, action.target_key)}”", :good ]
      when "wait" then [ "Waited for new messages", :neutral ]
      when "end_shift" then [ "Ended the shift", :neutral ]
      else [ action.kind.humanize, :neutral ]
      end

    [ action.minute, description, tone ]
  end

  # Each red flag in a phish, and whether the player flagged it: [flag, found?].
  def debrief_red_flags(result)
    result.message.red_flags.map { |flag| [ flag, flag.anchor.in?(result.flagged) ] }
  end

  # The parts the player flagged that weren't giveaways.
  def debrief_false_flags(result)
    return if result.false_flags.empty?

    parts = result.false_flags.map { |anchor| anchor_label(result.message, anchor) }.to_sentence
    if result.phish?
      "You also flagged #{parts}, which #{result.false_flags.one? ? "wasn't a giveaway" : "weren't giveaways"} " \
        "(#{debrief_points(result.false_flags.size * ShiftAttempt::Scorecard::FALSE_FLAG)})."
    else
      "You flagged #{parts}, but this #{message_noun(result.message)} was genuine (#{debrief_points(result.false_flags.size * ShiftAttempt::Scorecard::FALSE_FLAG)})."
    end
  end

  def debrief_task_timing(task_result)
    task = task_result.task
    case task_result.status
    when :on_time then "Done at minute #{task_result.completed_at_minute}, due by #{task.due_at_minute}"
    when :late then "Done at minute #{task_result.completed_at_minute}, #{task_result.completed_at_minute - task.due_at_minute} min late"
    else "Not done (due by minute #{task.due_at_minute})"
    end
  end

  # What to call a message in a sentence: an email, a text or a chat message.
  def message_noun(message)
    ShiftAttemptsHelper::CHANNEL_NAMES.fetch(message.channel).fetch(:noun)
  end

  private
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
        "You entered a password on the fake sign-in page at #{tab.host}. In a real attack Red now has your password: " \
          "they could read your email and send phish to your colleagues from your account."
      elsif tab.attachment
        "You opened #{tab.file_name}. It wasn't a document: it was a program in disguise, and it started encrypting your files."
      else
        "You ran #{tab.file_name}, downloaded from #{tab.host}. It was malware, and it started encrypting your files."
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

    def task_title(scorecard, key)
      scorecard.tasks.find { |task_result| task_result.task.key == key }&.task&.title || "a task"
    end

    def quoted_titles(tasks)
      tasks.map { |task| "“#{task.title}”" }.to_sentence
    end
end
