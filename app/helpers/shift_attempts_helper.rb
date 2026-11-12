module ShiftAttemptsHelper
  # A button for one move in a shift, labelled with what it costs and disabled when it won't fit in
  # the time left. The URL names the move and, for message moves, only the message's opaque ref.
  def shift_action_button(attempt, label, path, cost: 0, **options)
    button_to cost.positive? ? "#{label} (#{cost} min)" : label, path,
      disabled: !attempt.affordable?(cost),
      class: options.fetch(:class, "btn-ghost"),
      form: { class: "contents" }
  end

  # The page each landing shows in the in-game browser. Partial names are neutral ("sign_in", not
  # "credential_harvest") because they can surface in error pages and logs.
  LANDING_PARTIALS = {
    "portal_task" => "shift_attempts/landings/portal",
    "credential_harvest" => "shift_attempts/landings/sign_in",
    "malware_download" => "shift_attempts/landings/download",
    "file_preview" => "shift_attempts/landings/document",
    "harmless" => "shift_attempts/landings/article"
  }.freeze

  def landing_partial(tab)
    LANDING_PARTIALS.fetch(tab.landing)
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
