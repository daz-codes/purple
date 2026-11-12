module ShiftAttemptsHelper
  # A button that POSTs one game action. Only the action kind and the message's opaque ref
  # (ShiftAttempt#message_ref) go in the form; the server works out everything else.
  def shift_action_button(attempt, kind, label, message: nil, cost: attempt.shift.action_cost(kind), **options)
    text = cost.positive? ? "#{label} (#{cost} min)" : label
    button_to text, shift_attempt_actions_path(attempt),
      params: { kind:, message: (attempt.message_ref(message) if message) }.compact,
      disabled: cost > attempt.minutes_left,
      class: options.fetch(:class, "btn-ghost"),
      form: { class: options.fetch(:form_class, "contents") }
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
