# Plays a shift with strategies that take no care at all, to check they never pay: reporting
# everything, archiving everything, clocking off at once, and flagging every sentence then reporting
# everything. Each must score below one star, and below a careful player. The importer runs this for
# every shift, and the scorecard tests run it on the fixtures.
#
# Lazy play is scored at its best: in timed mode, as fast as possible (a cleared inbox in no time
# earns the most speed bonus there is).
class Shift::LazyPlay
  STRATEGIES = %i[ report_everything archive_everything clock_off_at_once flag_every_sentence_then_report ].freeze

  def initialize(shift)
    @shift = shift
    @messages = shift.messages.includes(:red_flags, :links).to_a
  end

  # The strategies that score one star or more, or at least as well as careful play, with their scorecards.
  def exploits
    careful_total = careful.total
    STRATEGIES.to_h { |strategy| [ strategy, scorecard(strategy) ] }
      .select { |_, card| card.stars >= 1 || card.total >= careful_total }
  end

  def scorecard(strategy)
    actions = strategy == :clock_off_at_once ? [ action("clock_off", nil) ] : deal_with_everything(strategy)
    score(actions, cleared: strategy != :clock_off_at_once)
  end

  # Every message handled as it should be, with every red flag found.
  def careful
    actions = []
    until (pending = pending(actions)).empty?
      pending.each { |message| actions.concat(careful_moves(message)) }
    end
    score(actions, cleared: true)
  end

  private
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

    def careful_moves(message)
      return message.red_flags.map { |red_flag| flag(message, red_flag_flag(red_flag)) } + [ action("report_message", message) ] if message.phish?

      moves = case message.expects
      when "act" then [ action("use_portal", message) ]
      when "reply" then [ action("send_reply", message, result: message.replies.find { |reply| reply["outcome"].in?(%w[ safe verify ]) }) ]
      else []
      end
      moves + [ action("archive_message", message) ]
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
