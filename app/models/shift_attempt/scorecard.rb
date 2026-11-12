# The score for a shift, worked out from its action log. A pure function of the shift's content and
# the actions: it reads nothing else and changes nothing, so the same log always gives the same score.
# The Purple debrief is rendered from it too, so the score and its explanation can't disagree.
#
# Productivity: a task completed on time earns its points, late earns half, never completed loses
# half. Security is judged message by message: +30 for reporting a phish, -15 for reporting a
# legitimate message, -10 for each near miss (a bait page or malware download opened but not fallen
# for), -50 for each compromise (a password entered or a download run), plus each red flag's points
# when it's flagged and -5 for each flag on something that isn't one. Flagging can't cost points
# overall: its total across the shift is never below 0. Each hint takes its penalty_percent of the
# maximum score off the total. Total = productivity + security - hints, never below 0.
#
# clock_minutes: the minute the shift ended (or has reached). Every message in the shift is judged,
# including any that arrived after the player ended the shift early: a phish they left behind still
# counts as not reported, so ending early is never a way to dodge the rest of the day's mail.
class ShiftAttempt::Scorecard
  REPORTED_PHISH = 30
  REPORTED_LEGIT = -15
  NEAR_MISS = -10
  COMPROMISED = -50
  FALSE_FLAG = -5

  # Share of the maximum score needed for each star. Three stars also need no compromise.
  STAR_THRESHOLDS = [ 0.3, 0.6, 0.9 ].freeze

  TaskResult = Data.define(:task, :status, :points, :completed_at_minute) do
    def on_time? = status == :on_time
    def late? = status == :late
    def missed? = status == :missed
  end

  HintUsed = Data.define(:hint, :penalty)

  # What the player did with one message, and what it scored. compromises and near_misses are the
  # ShiftAttempt::Tabs (pages or files) involved; completed_tasks are tasks done through its links;
  # flagged are the anchors the player left flagged; arrived is false for a message that came after
  # the shift ended.
  MessageResult = Data.define(:message, :actions, :compromises, :near_misses, :completed_tasks, :flagged, :arrived) do
    def phish? = message.phish?
    def arrived? = arrived
    def opened? = actions.any?(&:open_message?)
    def verified? = actions.any?(&:verify_sender?)
    def reported? = actions.any?(&:report_message?)
    def compromised? = compromises.any?
    def near_miss? = near_misses.any?

    def reported_at_minute
      actions.find(&:report_message?)&.minute
    end

    # The headline for the debrief.
    #   phish:      :compromised, :reported, :near_miss, :not_reported or :arrived_after_shift
    #   legitimate: :reported_wrongly, :used or :left_alone
    def outcome
      if phish?
        if !arrived? then :arrived_after_shift
        elsif compromised? then :compromised
        elsif reported? then :reported
        elsif near_miss? then :near_miss
        else :not_reported
        end
      else
        if reported? then :reported_wrongly
        elsif completed_tasks.any? then :used
        else :left_alone
        end
      end
    end

    def points
      report_points + near_misses.size * NEAR_MISS + compromises.size * COMPROMISED + flag_points
    end

    def best_points
      phish? ? REPORTED_PHISH + message.red_flags.sum(&:points) : 0
    end

    def found_flags
      message.red_flags.select { |flag| flag.anchor.in?(flagged) }
    end

    def missed_flags
      message.red_flags - found_flags
    end

    # Flagged anchors that aren't red flags.
    def false_flags
      flagged - message.red_flags.map(&:anchor)
    end

    def flag_points
      found_flags.sum(&:points) + false_flags.size * FALSE_FLAG
    end

    def report_points
      return 0 unless reported?

      phish? ? REPORTED_PHISH : REPORTED_LEGIT
    end
  end

  def initialize(shift:, actions:, clock_minutes: nil)
    @shift = shift
    @actions = actions
    @clock_minutes = clock_minutes
  end

  def productivity
    tasks.sum(&:points)
  end

  # Flagging's total across the shift is never below 0, so wrong flags can't cost more than the
  # right ones earned.
  def security
    messages.sum(&:points) - [ messages.sum(&:flag_points), 0 ].min
  end

  def total
    [ productivity + security - hint_penalty, 0 ].max
  end

  # The hints the player took, each with the points it cost.
  def hints
    @hints ||= @actions.select(&:use_hint?).filter_map do |action|
      hint = @shift.hints.find { |candidate| candidate.position == action.result["hint"] } or next
      HintUsed.new(hint:, penalty: (total_max * hint.penalty_percent / 100.0).round)
    end
  end

  def hint_penalty
    hints.sum(&:penalty)
  end

  def productivity_max
    @shift.tasks.sum(&:points)
  end

  def security_max
    messages.sum(&:best_points)
  end

  def total_max
    productivity_max + security_max
  end

  def perfect?
    productivity == productivity_max && security == security_max && hints.none?
  end

  def compromised?
    messages.any?(&:compromised?)
  end

  # 0 to 3.
  def stars
    return 0 unless total_max.positive?

    stars = STAR_THRESHOLDS.count { |threshold| total >= total_max * threshold }
    compromised? ? [ stars, 2 ].min : stars
  end

  def tasks
    @tasks ||= task_results(open: false)
  end

  # Every message in the shift, in the order it arrives.
  def messages
    @messages ||= shift_messages.map { |message| message_result(message) }
  end

  def phishes
    messages.select(&:phish?)
  end

  def message_result_for(key)
    messages.find { |result| result.message.key == key }
  end

  # Meters shown in the header during a shift. They only reflect what the player already knows:
  # tasks they've completed and compromises they've seen happen. Whether a report was right, or
  # whether a page they closed was a trap, stays hidden until the debrief: otherwise the meter would
  # give the answer away.
  def productivity_meter
    earned = task_results(open: true).sum(&:points)
    productivity_max.zero? ? 0 : (100 * earned / productivity_max).clamp(0, 100)
  end

  def security_meter
    compromises = @actions.select { |action| action.kind.in?(ShiftAttempt::Compromisable::COMPROMISING_KINDS) }
      .uniq { |action| [ action.target_key, action.result ] }
    (100 + compromises.size * COMPROMISED).clamp(0, 100)
  end

  private
    # While the shift is open, a task that isn't done yet hasn't been missed.
    def task_results(open:)
      completions = first_actions(:complete_task)

      @shift.tasks.map do |task|
        completion = completions[task.key]
        if completion.nil?
          TaskResult.new(task:, status: :missed, points: open ? 0 : -(task.points / 2), completed_at_minute: nil)
        else
          finished = completion.finished_at_minute
          on_time = finished <= task.due_at_minute
          TaskResult.new(task:, status: on_time ? :on_time : :late, points: on_time ? task.points : task.points / 2,
            completed_at_minute: finished)
        end
      end
    end

    # A message removed by a later content import no longer counts either way.
    def shift_messages
      @shift.messages.includes(:techniques, :red_flags, links: :task)
        .sort_by { |message| [ message.arrives_at_minute, message.position ] }
    end

    def arrived?(message)
      @clock_minutes.nil? || message.arrives_at_minute <= @clock_minutes
    end

    def message_result(message)
      actions = @actions.select { |action| action.target_key == message.key }
      compromises = tabs(message, actions, ShiftAttempt::Compromisable::COMPROMISING_KINDS)
      # Each bait page or malware download the player opened without falling for it.
      near_misses = tabs(message, actions, ShiftAttempt::Browsing::TAB_OPENERS).select(&:trap?)
        .reject { |tab| compromises.any? { |compromise| compromise.same_page?(tab) } }

      MessageResult.new(message:, actions:, compromises:, near_misses:, completed_tasks: completed_tasks(message),
        flagged: ShiftAttempt::Flaggable.standing_anchors(actions), arrived: arrived?(message))
    end

    # The pages or files the given kinds of action happened on, once each. Uses the same rules as
    # the page the browser showed, so scoring can't disagree with it.
    def tabs(message, actions, kinds)
      actions.select { |action| action.kind.in?(kinds) }.map(&:result).uniq
        .map { |source| ShiftAttempt::Tab.new(message:, source:) }
    end

    def completed_tasks(message)
      done = first_actions(:complete_task)
      message.links.select(&:outcome_completes_task?).map(&:task).select { |task| done.key?(task.key) }.uniq
    end

    def first_actions(kind)
      @first_actions ||= {}
      @first_actions[kind] ||= @actions.select { |action| action.kind == kind.to_s }.uniq(&:target_key).index_by(&:target_key)
    end
end
