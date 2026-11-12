# Every move a player makes in a shift is a POST here. Shift::Engine decides whether it's allowed,
# records it and moves the clock on; the response re-renders the clock, meters and panes.
class ShiftAttemptActionsController < ApplicationController
  include ShiftAttemptScoped
  rate_limit to: 120, within: 1.minute,
    with: -> { reject "You're clicking too fast. Wait a moment and try again." }

  def create
    arrived_before = @attempt.arrived_messages.count
    Shift::Engine.new(@attempt).perform(params[:kind], message_ref: params[:message])
    return redirect_to(@attempt, status: :see_other) if @attempt.finished?

    @notice = new_mail_notice(@attempt.arrived_messages.count - arrived_before)
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to @attempt, notice: @notice }
    end
  rescue Shift::Engine::Rejected => rejection
    reject rejection.message
  end

  private
    def reject(message)
      @attempt.reload
      return redirect_to(@attempt, status: :see_other) if @attempt.finished?

      respond_to do |format|
        format.turbo_stream { render turbo_stream: turbo_stream.update("shift_notice", partial: "shift_attempts/notice", locals: { message:, alert: true }), status: :unprocessable_content }
        format.html { redirect_to @attempt, alert: message }
      end
    end

    def new_mail_notice(count)
      "#{count} new #{"message".pluralize(count)} arrived." if count.positive?
    end
end
