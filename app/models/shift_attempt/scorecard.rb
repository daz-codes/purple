# The score for a shift, worked out from its action log. A pure function of the shift's content and
# the actions: it reads nothing else and changes nothing, so the same log always gives the same score.
#
# Productivity: a task completed on time earns its points, late earns half, never completed loses
# half. Security: +30 for each phish reported, -15 for each legitimate message reported, -10 for each
# near miss (a bait page or malware download opened but not fallen for), -50 for each compromise
# (a password entered or a download run). Total = productivity + security, never below 0.
#
# Red flags and hints arrive in M5.
class ShiftAttempt::Scorecard
  REPORTED_PHISH = 30
  REPORTED_LEGIT = -15
  NEAR_MISS = -10
  COMPROMISED = -50

  TaskResult = Data.define(:task, :status, :points) do
    def on_time? = status == :on_time
    def late? = status == :late
    def missed? = status == :missed
  end

  def initialize(shift:, actions:)
    @shift = shift
    @actions = actions
  end

  def productivity
    tasks.sum(&:points)
  end

  def security
    reports_score + near_misses.size * NEAR_MISS + compromises.size * COMPROMISED
  end

  def total
    [ productivity + security, 0 ].max
  end

  def tasks
    @tasks ||= task_results(open: false)
  end

  # Meters shown in the header during a shift. They only reflect what the player already knows:
  # tasks they've completed and compromises they've seen happen. Whether a report was right, or
  # whether a page they closed was a trap, stays hidden until the debrief: otherwise the meter would
  # give the answer away.
  def productivity_meter
    earned = task_results(open: true).sum(&:points)
    maximum = @shift.tasks.sum(&:points)
    maximum.zero? ? 0 : (100 * earned / maximum).clamp(0, 100)
  end

  def security_meter
    (100 + compromises.size * COMPROMISED).clamp(0, 100)
  end

  private
    # While the shift is open, a task that isn't done yet hasn't been missed.
    def task_results(open:)
      completions = first_actions(:complete_task)

      @shift.tasks.map do |task|
        completion = completions[task.key]
        if completion.nil?
          TaskResult.new(task:, status: :missed, points: open ? 0 : -(task.points / 2))
        elsif completion.finished_at_minute <= task.due_at_minute
          TaskResult.new(task:, status: :on_time, points: task.points)
        else
          TaskResult.new(task:, status: :late, points: task.points / 2)
        end
      end
    end

    def reports_score
      # A message removed by a later content import no longer counts either way.
      first_actions(:report_message).keys.sum do |key|
        message = messages[key]
        next 0 unless message

        message.legit? ? REPORTED_LEGIT : REPORTED_PHISH
      end
    end

    # Each trap the player fell for, once per page or file: [message key, source].
    def compromises
      @compromises ||= sources_of(ShiftAttempt::Compromisable::COMPROMISING_KINDS)
    end

    # Each bait page or malware download the player opened without falling for it.
    def near_misses
      @near_misses ||= sources_of(ShiftAttempt::Browsing::TAB_OPENERS).select { |source| trap?(*source) } - compromises
    end

    def sources_of(kinds)
      @actions.select { |action| action.kind.in?(kinds) }.map { |action| [ action.target_key, action.result ] }.uniq
    end

    # Uses the same rules as the page the browser showed, so scoring can't disagree with it.
    def trap?(message_key, source)
      message = messages[message_key] or return false

      ShiftAttempt::Tab.new(message:, source:).trap?
    end

    def messages
      @messages ||= @shift.messages.includes(:links).index_by(&:key)
    end

    def first_actions(kind)
      @actions.select { |action| action.kind == kind.to_s }.uniq(&:target_key).index_by(&:target_key)
    end
end
