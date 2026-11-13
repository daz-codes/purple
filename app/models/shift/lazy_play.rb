# Plays a shift with strategies that take no care at all, to check they never pay: reporting
# everything, archiving everything, clocking off at once, and flagging every sentence then reporting
# everything. Each must score below one star, and below a careful player. The importer runs this for
# every shift, and the scorecard tests run it on the fixtures.
#
# A shift whose messages ask for private details is also played three ways with them: sharing
# everything with everyone, and sharing whatever's asked (the careless player who gives each asker what
# it requests) must also score below one star; sharing nothing at all must earn fewer stars than
# careful play, so refusing everything never works either.
#
# Lazy play is scored at its best: in timed mode, as fast as possible (a cleared inbox in no time
# earns the most speed bonus there is).
class Shift::LazyPlay
  STRATEGIES = %i[ report_everything archive_everything clock_off_at_once flag_every_sentence_then_report ].freeze
  DETAIL_STRATEGIES = %i[ share_everything_with_everyone share_whatever_asked ].freeze

  def initialize(shift)
    @shift = shift
    @messages = shift.messages.includes(:red_flags, :links).to_a
  end

  # The strategies that score one star or more, or at least as well as careful play, with their scorecards.
  def exploits
    best = careful
    strategies = STRATEGIES + (@shift.asks_for_details? ? DETAIL_STRATEGIES : [])
    found = strategies.to_h { |strategy| [ strategy, scorecard(strategy) ] }
      .select { |_, card| card.stars >= 1 || card.total >= best.total }
    if @shift.asks_for_details?
      nothing = scorecard(:share_nothing)
      found[:share_nothing] = nothing if nothing.stars >= best.stars || nothing.total >= best.total
    end
    found
  end

  def scorecard(strategy)
    actions = case strategy
    when :clock_off_at_once then [ action("clock_off", nil) ]
    when :share_nothing then careful_actions(share: false)
    when *DETAIL_STRATEGIES then sharing(strategy)
    else deal_with_everything(strategy)
    end
    score(actions, cleared: strategy != :clock_off_at_once)
  end

  # Every message handled as it should be, with every red flag found.
  def careful
    score(careful_actions, cleared: true)
  end

  private
    def careful_actions(share: true)
      actions = []
      until (pending = pending(actions)).empty?
        pending.each { |message| actions.concat(careful_moves(message, share:)) }
      end
      actions
    end

    # Careful handling, except for what's shared: everything with every message that has somewhere to
    # put it, or (whatever's asked) each phish gets what it wants and is archived, unsuspected.
    def sharing(strategy)
      actions = []
      until (pending = pending(actions)).empty?
        pending.each do |message|
          if strategy == :share_everything_with_everyone
            actions.concat(share(message, details))
            actions.concat(careful_moves(message, share: false))
          elsif message.phish?
            actions.concat(share(message, message.wants.filter_map { |key| detail(key) }))
            actions << action("archive_message", message)
          else
            actions.concat(careful_moves(message))
          end
        end
      end
      actions
    end

    def deal_with_everything(strategy)
      actions = []
      until (pending = pending(actions)).empty?
        pending.each do |message|
          actions.concat(every_sentence(message)) if strategy == :flag_every_sentence_then_report
          actions << action(strategy == :archive_everything ? "archive_message" : "report_message", message)
        end
      end
      actions
    end

    def pending(actions)
      handled = actions.select(&:handling?).map(&:target_key)
      ShiftAttempt::Arrivals.new(@messages, actions).messages.reject { |message| message.key.in?(handled) }
    end

    def careful_moves(message, share: true)
      return message.red_flags.map { |red_flag| flag(message, red_flag_flag(red_flag)) } + [ action("report_message", message) ] if message.phish?

      needed = share ? message.needs.filter_map { |key| detail(key) } : []
      moves = case message.expects
      when "act" then share(message, needed) + [ action("use_portal", message) ]
      when "reply"
        reply = message.replies.find { |reply| reply["outcome"].in?(%w[ safe verify ]) }
        share(message, needed) + (message.needs.empty? ? [ action("send_reply", message, result: reply) ] : [])
      else []
      end
      moves + [ action("archive_message", message) ]
    end

    # Sharing details with a message: on its page if it has a portal or lookalike sign-in page, otherwise
    # in its Send details box if it has replies. A message with neither can't be given anything.
    def share(message, given)
      return [] if given.empty?

      via = if message.links.any? { |link| link.landing_template.in?(%w[ portal credential_harvest ]) } then "page"
      elsif message.replies.any? then "reply"
      end
      return [] unless via

      shared = given.map { |detail| { "chip" => detail.key, "label" => detail.label, "detail" => detail.key, "sensitivity" => detail.sensitivity } }
      [ action("share_details", message, result: { "via" => via, "shared" => shared }) ]
    end

    def details
      @details ||= @shift.details
    end

    def detail(key)
      details.find { |detail| detail.key == key }
    end

    def every_sentence(message)
      message.paragraphs.values.flat_map do |paragraph|
        paragraph.sentences.filter_map do |sentence|
          from, to = paragraph.trim(sentence.from, sentence.to)
          flag(message, ShiftAttempt::Flag.new(anchor: paragraph.anchor, from:, to:)) if from
        end
      end
    end

    def red_flag_flag(red_flag)
      if red_flag.quote?
        ShiftAttempt::Flag.new(anchor: red_flag.anchor, from: red_flag.quote_start, to: red_flag.quote_end)
      else
        ShiftAttempt::Flag.new(anchor: red_flag.anchor, from: nil, to: nil)
      end
    end

    def flag(message, flag)
      action("flag_element", message, result: flag.to_result)
    end

    def action(kind, message, result: {})
      AttemptAction.new(kind:, target_key: message.is_a?(Message) ? message.key : message, at_seconds: 0, penalty_seconds: 0, result: result || {})
    end

    def score(actions, cleared:)
      ShiftAttempt::Scorecard.new(shift: @shift, actions:, elapsed_seconds: 0, cleared:, relaxed: false)
    end
end
