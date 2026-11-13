# XP in the debriefs: what a finished shift or campaign earned.
module ProgressHelper
  REASONS = { "shift_completed" => "for the shift", "workshop_completed" => "for the campaign", "streak_bonus" => "first play today" }.freeze

  # [[amount, words], ...] for the XP this shift or campaign earned the player.
  def xp_earned_by(source)
    Current.user.xp_events.where(source:).map { |event| [ event.amount, REASONS.fetch(event.reason, event.reason.humanize) ] }
  end

  def xp_note(source)
    return "Confirm your email address to earn XP." unless Current.user.earns_xp?
    return "This replay doesn't earn XP: only your first finished attempt does." if xp_earned_by(source).none? { |_, words| words != "first play today" }

    nil
  end
end
