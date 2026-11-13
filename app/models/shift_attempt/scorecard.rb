# The score for a shift, worked out from its action log. A pure function of the shift's content and
# the actions (plus how long the attempt took): it reads nothing else and changes nothing, so the same
# log always gives the same score. The Purple debrief is rendered from it too, so the score and its
# explanation can't disagree. Nothing here is shown until the shift is over.
#
# Every message is judged on what it expected:
# - A genuine message is worth its points when the player did what it needed: sent a reply that wasn't
#   poor, did the thing on its portal page, or (for one that needed nothing) archived it. Half if it
#   was urgent and done late. Archiving it without doing what it needed, or sending a poor reply,
#   loses half its points. Still unhandled when the shift ended (in the inbox, or yet to arrive) also
#   loses half, unless it only needed archiving: then it costs nothing. Reporting it costs 15.
# - A phish is worth 30 when reported. Each near miss (a bait page or malware download opened but not
#   fallen for) costs 10, and each compromise (a password entered, a file run, or a reply that handed
#   something over) costs 50.
# - Each red flag found earns its points, and each flag that finds nothing costs 10, on any message.
# - Private details (Shift::Detail). A genuine message that needs details is only done once it has all
#   of them, through the right channel: secrets and the MFA code only on its portal page, never in a
#   message. Sharing a detail it didn't need is oversharing: -5 for an internal detail, -15 for a
#   secret (a secret sent in a message always counts as overshared). Giving a phish anything above
#   public costs -20 per internal detail and -50 per secret or MFA code, at most -50 in all, and counts
#   as a compromise. The MFA code anywhere but the sign-in page that asked for it is a compromise too.
#
# Clearing the inbox in timed mode earns a speed bonus: 20 points for each full 5 minutes under the
# shift's target time, times the share of messages handled as expected (phishes reported, genuine
# messages done), so rushing through and getting things wrong earns little. Each hint takes its penalty_percent of the maximum score off the total.
# Total = messages + speed bonus - hints, never below 0. Relaxed mode has no speed bonus and no
# lateness.
class ShiftAttempt::Scorecard
  REPORTED_PHISH = 30
  REPORTED_GENUINE = -15
  NEAR_MISS = -10
  COMPROMISED = -50
  FALSE_FLAG = -10
  SPEED_BLOCK_SECONDS = 5 * 60
  SPEED_BLOCK_POINTS = 20

  # Share of the maximum score needed for each star. Three stars also need no compromise.
  STAR_THRESHOLDS = [ 0.3, 0.6, 0.9 ].freeze

  HintUsed = Data.define(:hint, :penalty)

  # What the player did with one message, and what it scored. compromises and near_misses are the
  # ShiftAttempt::Tabs (pages or files) involved; flags are the ShiftAttempt::Flags left standing;
  # reply is the canned reply sent, as stored when it was sent; arrived_at is when it arrived (in
  # seconds into the attempt), or nil if it never did.
  # shares are the details handed over to it, each as stored when shared (see ShiftAttempt::Sharing) plus
  # how ("via": reply or page) and when ("at", in seconds).
  MessageResult = Data.define(:message, :actions, :compromises, :near_misses, :flags, :reply, :shares, :arrived_at, :relaxed) do
    def phish? = message.phish?
    def arrived? = !arrived_at.nil?
    def opened? = actions.any?(&:open_message?)
    def verified? = actions.any?(&:verify_sender?)
    def checked_first? = reply&.dig("outcome") == "verify"
    def reported? = actions.any?(&:report_message?)
    def archived? = actions.any?(&:archive_message?)
    def used_portal? = actions.any?(&:use_portal?)
    def gave_in? = ShiftAttempt::Replyable.gave_in?(reply)
    def compromised? = compromises.any? || gave_in? || leaks.any?
    def near_miss? = near_misses.any?
    def replied_well? = reply.present? && reply["outcome"].in?(%w[ safe verify ])
    def replied_poorly? = reply&.dig("outcome") == "poor"

    # When the player did what a genuine message needed, in seconds into the attempt, or nil. One that
    # needs details is done once it has them all; on a portal page, once the page is used too.
    def done_at_seconds
      return needed_details_at_seconds if message.needs.any? && message.expects_reply?

      action = case message.expects
      when "reply" then actions.find { |action| action.send_reply? } if replied_well?
      when "act" then actions.find(&:use_portal?)
      when "archive" then actions.find(&:archive_message?)
      end
      return action&.at_seconds if message.needs.empty? || action.nil?

      needed = needed_details_at_seconds
      [ action.at_seconds, needed ].max if needed
    end

    # --- Private details -----------------------------------------------------------------

    # When the last detail it needed arrived through the right channel, or nil if one never did.
    def needed_details_at_seconds
      given = Set.new
      shares.each do |share|
        given << share["detail"] if needed?(share)
        return share["at"] if message.needs.all? { |key| given.include?(key) }
      end
      nil
    end

    def needs_met? = !needed_details_at_seconds.nil?

    # A share this message needed, through a channel it may take: secrets and the MFA code only on a page.
    def needed?(share)
      share["detail"].in?(message.needs) && (share["via"] == "page" || !page_only?(share))
    end

    # What a phish was given that's above public: falling for it.
    def leaks
      return mfa_misuses unless phish?

      shares.select { |share| share["sensitivity"].in?(%w[ internal secret never ]) }
    end

    # Details a genuine message was given that it didn't need (or a secret sent in a message).
    def overshares
      return [] if phish?

      shares.select { |share| share["sensitivity"].in?(%w[ internal secret ]) && !needed?(share) }
    end

    # The MFA code given to a genuine message anywhere but the sign-in page that asked for it.
    def mfa_misuses
      shares.select { |share| share["sensitivity"] == "never" && !needed?(share) }
    end

    def detail_points
      if phish?
        [ leaks.sum { |share| Shift::Detail::LEAK_POINTS.fetch(share["sensitivity"]) }, COMPROMISED ].max
      else
        overshares.sum { |share| Shift::Detail::OVERSHARE_POINTS.fetch(share["sensitivity"]) } + (mfa_misuses.any? ? COMPROMISED : 0)
      end
    end

    def page_only?(share) = share["sensitivity"].in?(%w[ secret never ])

    def done? = !phish? && !reported? && !done_at_seconds.nil?

    # Phishes reported, genuine messages done: what the speed bonus is scaled by.
    def handled_as_expected?
      phish? ? reported? : done?
    end

    def late?
      done? && !relaxed && message.urgent_within_minutes.present? &&
        done_at_seconds - arrived_at > message.urgent_within_minutes * 60
    end

    # The headline for the debrief.
    #   phish:   :compromised, :reported, :near_miss, :not_reported or :never_arrived
    #   genuine: :reported_wrongly, :done, :done_late, :not_done or :never_arrived
    def outcome
      if !arrived? then :never_arrived
      elsif phish?
        if compromised? then :compromised
        elsif reported? then :reported
        elsif near_miss? then :near_miss
        else :not_reported
        end
      elsif reported? then :reported_wrongly
      elsif late? then :done_late
      elsif done? then :done
      else :not_done
      end
    end

    def points
      handling_points + flag_points
    end

    def handling_points
      action_points + detail_points
    end

    def action_points
      if phish?
        (reported? ? REPORTED_PHISH : 0) + near_misses.size * NEAR_MISS + (compromises.size + (gave_in? ? 1 : 0)) * COMPROMISED
      elsif reported? then REPORTED_GENUINE
      elsif done? then late? ? message.points / 2 : message.points
      elsif archived? || replied_poorly? then -(message.points / 2)
      elsif message.expects_archive? then 0
      else -(message.points / 2)
      end
    end

    def best_points
      phish? ? REPORTED_PHISH + message.red_flags.sum(&:points) : message.points
    end

    def found_flags
      message.red_flags.select { |red_flag| flags.any? { |flag| red_flag.found_by?(flag) } }
    end

    def missed_flags
      message.red_flags - found_flags
    end

    # Flags that found no red flag.
    def false_flags
      flags.reject { |flag| message.red_flags.any? { |red_flag| red_flag.found_by?(flag) } }
    end

    def flag_points
      found_flags.sum(&:points) + false_flags.size * FALSE_FLAG
    end
  end

  # elapsed_seconds: how long the attempt took, penalties included. cleared: whether the player dealt
  # with every message (rather than clocking off early or leaving it to expire); only a cleared inbox earns the
  # speed bonus.
  # arrivals: the attempt's ShiftAttempt::Arrivals, if it has already worked them out.
  def initialize(shift:, actions:, arrivals: nil, elapsed_seconds: nil, cleared: false, relaxed: false)
    @shift = shift
    @actions = actions
    @arrivals = arrivals
    @elapsed_seconds = elapsed_seconds
    @cleared = cleared
    @relaxed = relaxed
  end

  attr_reader :elapsed_seconds

  def relaxed? = @relaxed
  def cleared? = @cleared

  def message_points
    messages.sum(&:points)
  end

  def speed_bonus
    return 0 if relaxed? || !cleared? || elapsed_seconds.nil? || messages.empty?

    blocks = [ (@shift.par_minutes * 60 - elapsed_seconds) / SPEED_BLOCK_SECONDS, 0 ].max
    (blocks * SPEED_BLOCK_POINTS * accuracy).round
  end

  # The share of messages handled as expected, from 0 to 1.
  def accuracy
    messages.count(&:handled_as_expected?).fdiv(messages.size)
  end

  def total
    [ message_points + speed_bonus - hint_penalty, 0 ].max
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

  # The best the messages can score. Stars and hint penalties are judged against this; the speed bonus
  # is extra on top.
  def total_max
    messages.sum(&:best_points)
  end

  # The most the speed bonus could add: clearing everything correctly in no time.
  def speed_bonus_max
    relaxed? ? 0 : (@shift.par_minutes * 60 / SPEED_BLOCK_SECONDS) * SPEED_BLOCK_POINTS
  end

  # What the total is shown out of, so a score can never read as more than its maximum.
  def best_possible
    total_max + speed_bonus_max
  end

  def perfect?
    messages.all? { |result| result.points == result.best_points } && hints.none?
  end

  def compromised?
    messages.any?(&:compromised?)
  end

  # Every detail given to a phish, once each, for "What Red now knows".
  def leaked_details
    phishes.flat_map(&:leaks).uniq { |share| share["detail"] || share["chip"] }
  end

  # 0 to 3.
  def stars
    return 3 if perfect?
    return 0 unless total_max.positive?

    # Judged without the speed bonus, so rushing can't buy stars.
    without_bonus = [ total - speed_bonus, 0 ].max
    stars = STAR_THRESHOLDS.count { |threshold| without_bonus >= total_max * threshold }
    compromised? ? [ stars, 2 ].min : stars
  end

  # Every message in the shift: those that arrived, in the order they did, then any that never did.
  def messages
    @messages ||= begin
      arrivals = @arrivals || ShiftAttempt::Arrivals.new(shift_messages, @actions)
      arrived_at = arrivals.all.to_h { |arrival| [ arrival.message.key, arrival.at_seconds ] }
      ordered = shift_messages.sort_by { |message| [ arrived_at.key?(message.key) ? 0 : 1, arrived_at.keys.index(message.key) || message.position ] }
      ordered.map { |message| message_result(message, arrived_at[message.key]) }
    end
  end

  def phishes
    messages.select(&:phish?)
  end

  def genuine
    messages.reject(&:phish?)
  end

  def message_result_for(key)
    messages.find { |result| result.message.key == key }
  end

  private
    # A message removed by a later content import no longer counts either way.
    def shift_messages
      @shift_messages ||= @shift.messages.includes(:techniques, :red_flags, :links).to_a
    end

    # Moves can only be made on a message once it has arrived, so any logged against one that never did
    # (impossible in play) count for nothing.
    def message_result(message, arrived_at)
      actions = arrived_at ? @actions.select { |action| action.target_key == message.key } : []
      compromises = tabs(message, actions, ShiftAttempt::Compromisable::COMPROMISING_KINDS)
      # Each bait page or malware download the player opened without falling for it.
      near_misses = tabs(message, actions, ShiftAttempt::Browsing::TAB_OPENERS).select(&:trap?)
        .reject { |tab| compromises.any? { |compromise| compromise.same_page?(tab) } }

      shares = ShiftAttempt::Sharing.shares(actions).flat_map do |action|
        action.result["shared"].map { |shared| shared.merge("via" => action.result["via"], "at" => action.at_seconds) }
      end

      MessageResult.new(message:, actions:, compromises:, near_misses:, flags: ShiftAttempt::Flaggable.standing(actions),
        reply: ShiftAttempt::Replyable.sent(actions)[message.key], shares:, arrived_at:, relaxed: @relaxed)
    end

    # The pages or files the given kinds of action happened on, once each. Uses the same rules as
    # the page the browser showed, so scoring can't disagree with it.
    def tabs(message, actions, kinds)
      actions.select { |action| action.kind.in?(kinds) }.map(&:result).uniq
        .map { |source| ShiftAttempt::Tab.new(message:, source:) }
    end
end
