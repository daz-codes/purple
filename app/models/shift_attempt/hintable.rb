# Hints, revealed one at a time in the shift's order. A hint costs no time, but each one takes its
# penalty_percent of the maximum score off the total at the end (see Scorecard).
module ShiftAttempt::Hintable
  extend ActiveSupport::Concern

  def use_hint
    acting_on do
      hint = next_hint or reject "There are no more hints for this shift."

      record :use_hint, result: { "hint" => hint.position }
    end
  end

  # Read from the log, like everything else about the attempt.
  def hints_used
    used_hint_positions.size
  end

  def revealed_hints
    positions = used_hint_positions
    shift.hints.select { |hint| hint.position.in?(positions) }
  end

  def next_hint
    positions = used_hint_positions
    shift.hints.find { |hint| !hint.position.in?(positions) }
  end

  private
    def used_hint_positions
      actions.select(&:use_hint?).map { |action| action.result["hint"] }
    end
end
