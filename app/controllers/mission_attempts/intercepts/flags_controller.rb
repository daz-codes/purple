# Submits a flag for an intercept. The answer is free text (MissionAttempt::Decoding), so on top of the
# game's rate limit, flags have a tighter one: guessing quickly gets nowhere.
class MissionAttempts::Intercepts::FlagsController < ApplicationController
  # In this order: the attempt is found before its intercept.
  include MissionPlay
  include MissionAttemptInterceptScoped

  rate_limit to: 10, within: 1.minute, name: "flags",
    with: -> { refuse "That's a lot of guesses. Wait a minute, and work it out in the Workbench." }

  def create
    play { @notice = flag_notice(@attempt.submit_flag(@intercept, params[:answer])) }
  end

  private
    def flag_notice(correct)
      return "Flag found." if correct

      left = @attempt.tries_left(@intercept)
      left.positive? ? "Not that. #{left} #{"try".pluralize(left)} left on this intercept." : "Not that. That intercept is now closed."
    end
end
