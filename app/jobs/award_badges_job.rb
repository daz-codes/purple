# Checks what a player's just-finished shift or campaign has earned them, and tells them about any new
# badge with a toast.
class AwardBadgesJob < ApplicationJob
  queue_as :default

  def perform(user, source)
    user.award_badges_for(source).each do |badge|
      Turbo::StreamsChannel.broadcast_append_to user, :notifications, target: "toasts",
        partial: "badges/toast", locals: { badge: }
    end
  end
end
