class ApplicationController < ActionController::Base
  include Authentication
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  helper_method :unlocks

  private
    # Which paths, tracks and missions the player (or a visitor) can play.
    def unlocks
      @unlocks ||= User::Unlocks.new(authenticated? ? Current.user : nil)
    end
end
