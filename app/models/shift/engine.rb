class Shift
  # Applies a player's action to a shift attempt: checks it's allowed, records it in the log,
  # moves the clock on and ends the shift when it's over. The only way an attempt changes.
  #
  # Each action costs the shift's configured minutes (Shift#action_cost). An action that doesn't fit
  # in the time left is rejected rather than run past the end of the day. The shift ends when the
  # clock reaches the time budget, when every task is resolved (done, or impossible because its
  # message was reported), or when the player ends it.
  class Engine
    class Rejected < StandardError; end

    MESSAGE_ACTIONS = %w[ open_message expand_headers verify_sender report_message ].freeze
    PLAYER_ACTIONS = (MESSAGE_ACTIONS + %w[ wait ]).freeze

    attr_reader :attempt

    def initialize(attempt)
      @attempt = attempt
    end

    # kind: one of PLAYER_ACTIONS. message_ref: ShiftAttempt#message_ref of the message, for message actions.
    # Returns the recorded AttemptAction.
    def perform(kind, message_ref: nil)
      kind = kind.to_s
      raise Rejected, "That isn't something you can do in this shift." unless PLAYER_ACTIONS.include?(kind)

      attempt.with_lock do
        ensure_open!
        if kind == "wait"
          wait
        else
          message = attempt.find_arrived_message(message_ref) or raise Rejected, "That message isn't in your inbox."
          raise Rejected, "You've already reported that message." if attempt.reported?(message)

          case kind
          when "open_message" then open_message(message)
          when "expand_headers" then expand_headers(message)
          when "verify_sender" then verify_sender(message)
          when "report_message" then report_message(message)
          end
        end
      end
    end

    def end_shift
      attempt.with_lock do
        ensure_open!
        record("end_shift", cost: 0)
        finish!(:completed) # does nothing if recording the action already ended the shift
      end
    end

    # Reading is free.
    def open_message(message)
      record("open_message", message:)
    end

    # Shows the real addresses behind the display name.
    def expand_headers(message)
      raise Rejected, "You've already expanded those headers." if attempt.headers_expanded?(message)

      record("expand_headers", message:)
    end

    # Calls the sender back on a number you already hold. Their answer is scripted per message.
    def verify_sender(message)
      raise Rejected, "You've already checked with the sender." if attempt.sender_verified?(message)

      record("verify_sender", message:, result: { "reply" => message.verify_result.presence || "Nobody picked up." })
    end

    # Sends the message to the security team and removes it from the inbox. Whether that was right
    # is only revealed in the debrief.
    def report_message(message)
      record("report_message", message:)
    end

    # Lets time pass until the next message arrives.
    def wait
      next_arrival = attempt.next_arrival_minute or raise Rejected, "Nothing else is due today. End the shift when you're ready."

      record("wait", cost: next_arrival - attempt.clock_minutes)
    end

    private
      def ensure_open!
        raise Rejected, "This shift is over." unless attempt.open?
      end

      def record(kind, message: nil, cost: attempt.shift.action_cost(kind), result: {})
        if cost > attempt.minutes_left
          raise Rejected, "Not enough time left: that takes #{cost} min and you have #{attempt.minutes_left}."
        end

        action = attempt.attempt_actions.create!(kind:, target_key: message&.key, minute: attempt.clock_minutes,
                                                 cost_minutes: cost, result:)
        attempt.clock_minutes += cost
        attempt.save!
        attempt.reload

        if attempt.minutes_left.zero?
          finish!(:timed_out)
        elsif all_tasks_resolved?
          finish!(:completed)
        end

        action
      end

      # A task is resolved when it's done, or when every message that could complete it has been
      # reported. A task with no completing link at all isn't resolved: that's broken content, and
      # it mustn't end the shift.
      def all_tasks_resolved?
        tasks = attempt.shift.tasks.includes(links: :message)
        tasks.any? && tasks.all? do |task|
          completing = task.links.select(&:outcome_completes_task?)
          attempt.task_completed?(task) ||
            (completing.any? && completing.all? { |link| attempt.reported?(link.message) })
        end
      end

      def finish!(status)
        return unless attempt.open?

        result = attempt.scoring.call
        attempt.update!(status:, completed_at: Time.current, productivity_score: result.productivity,
                        security_score: result.security, score: result.total, scored: first_scored_attempt?)
      end

      # XP (from M8) is only for confirmed players' first finished attempt at each shift.
      def first_scored_attempt?
        attempt.user.earns_xp? &&
          !attempt.user.shift_attempts.scored.where.not(id: attempt.id).exists?(shift_id: attempt.shift_id)
      end
  end
end
