# Shared by the controllers for moves in a mission. Each one makes its move inside #play; the response
# re-renders the panes by Turbo Stream, or goes to the results if the mission ended.
# A move that isn't allowed changes nothing and tells the player why.
module MissionPlay
  extend ActiveSupport::Concern

  included do
    include MissionAttemptScoped

    rate_limit to: 120, within: 1.minute, with: -> { refuse "You're clicking too fast. Wait a moment and try again." }
    rescue_from MissionAttempt::Rejected, with: ->(rejection) { refuse rejection.message }
  end

  private
    # Nothing in the response says whether the move was right: no meters, no alerts. New messages
    # arriving is the one thing that's announced, since the inbox shows them anyway.
    def play
      arrived_before = @attempt.arrived_messages.size
      yield
      return redirect_to(@attempt, status: :see_other) if @attempt.finished?

      # A move can set its own notice (a flag's verdict); new mail is announced over it.
      @notice = new_mail_notice(@attempt.arrived_messages.size - arrived_before) || @notice
      respond_to do |format|
        format.turbo_stream { render "mission_attempts/play" }
        format.html { redirect_to @attempt, notice: @notice }
      end
    end

    def refuse(message)
      @attempt.reload
      return redirect_to(@attempt, status: :see_other) if @attempt.finished?

      respond_to do |format|
        format.turbo_stream do
          # The in-game browser is a modal, so anything behind it is hidden: tell the player in both places.
          render turbo_stream: %w[ mission_notice browser_notice ].map { |target|
            turbo_stream.update(target, partial: "mission_attempts/notice", locals: { message:, alert: true })
          }, status: :unprocessable_content
        end
        format.html { redirect_to @attempt, alert: message }
      end
    end

    def new_mail_notice(count)
      "#{count} new #{"message".pluralize(count)} arrived." if count.positive?
    end
end
