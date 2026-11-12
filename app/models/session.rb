class Session < ApplicationRecord
  # Signed out after this long without a request...
  IDLE_TIMEOUT = 2.weeks
  # ...and after this long regardless of activity.
  ABSOLUTE_TIMEOUT = 90.days
  # How often a session's last-activity time (updated_at) is written, to avoid a write per request.
  ACTIVITY_GRANULARITY = 1.hour

  belongs_to :user

  scope :active, -> { where(updated_at: IDLE_TIMEOUT.ago..).where(created_at: ABSOLUTE_TIMEOUT.ago..) }
  scope :expired, -> { where(updated_at: ...IDLE_TIMEOUT.ago).or(where(created_at: ...ABSOLUTE_TIMEOUT.ago)) }
  scope :most_recent_first, -> { order(updated_at: :desc) }

  BROWSERS = {
    "Edg" => "Edge", "OPR" => "Opera", "CriOS" => "Chrome", "FxiOS" => "Firefox",
    "Firefox" => "Firefox", "Chrome" => "Chrome", "Safari" => "Safari"
  }.freeze

  PLATFORMS = {
    "iPhone" => "iPhone", "iPad" => "iPad", "Android" => "Android", "Mac OS" => "macOS",
    "Windows" => "Windows", "Linux" => "Linux"
  }.freeze

  def record_activity
    touch if updated_at.before?(ACTIVITY_GRANULARITY.ago)
  end

  # A short, human-friendly description of the device, e.g. "Chrome on macOS".
  # Order matters: many user agents also mention Chrome/Safari (and iOS ones mention Mac OS).
  def device_description
    agent = user_agent.to_s
    browser = BROWSERS.find { |token, _| agent.include?(token) }&.last
    platform = PLATFORMS.find { |token, _| agent.include?(token) }&.last

    [ browser, platform ].compact.join(" on ").presence || "Unknown device"
  end
end
