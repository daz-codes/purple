# Shared by the controllers for moves in a shift. Each one makes its move inside #play; the response
# re-renders the clock, meters and panes by Turbo Stream, or goes to the results if the shift ended.
# A move that isn't allowed changes nothing and tells the player why.
module ShiftPlay
  extend ActiveSupport::Concern

  included do
    include ShiftAttemptScoped

    rate_limit to: 120, within: 1.minute, with: -> { refuse "You're clicking too fast. Wait a moment and try again." }
    rescue_from ShiftAttempt::Rejected, with: ->(rejection) { refuse rejection.message }
  end

  private
    # alert: what the player sees if the move went wrong for them (a compromise).
    def play(alert: nil)
      arrived_before = @attempt.arrived_messages.size
      yield
      return redirect_to(@attempt, status: :see_other, alert:) if @attempt.finished?

      @alert = alert.present?
      @notice = [ alert, new_mail_notice(@attempt.arrived_messages.size - arrived_before) ].compact.join(" ").presence
      respond_to do |format|
        format.turbo_stream { render "shift_attempts/play" }
        format.html { redirect_to @attempt, flash: { (@alert ? :alert : :notice) => @notice } }
      end
    end

    def refuse(message)
      @attempt.reload
      return redirect_to(@attempt, status: :see_other) if @attempt.finished?

      respond_to do |format|
        format.turbo_stream do
          # The in-game browser is a modal, so anything behind it is hidden: tell the player in both places.
          render turbo_stream: %w[ shift_notice browser_notice ].map { |target|
            turbo_stream.update(target, partial: "shift_attempts/notice", locals: { message:, alert: true })
          }, status: :unprocessable_content
        end
        format.html { redirect_to @attempt, alert: message }
      end
    end

    def new_mail_notice(count)
      "#{count} new #{"message".pluralize(count)} arrived." if count.positive?
    end
end
