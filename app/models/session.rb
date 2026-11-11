class Session < ApplicationRecord
  belongs_to :user

  scope :most_recent_first, -> { order(updated_at: :desc) }

  # A short, human-friendly description of the device, e.g. "Chrome on macOS".
  def device_description
    agent = user_agent.to_s
    browser = { "Edg" => "Edge", "Firefox" => "Firefox", "Chrome" => "Chrome", "Safari" => "Safari" }
      .find { |token, _| agent.include?(token) }&.last
    platform = { "iPhone" => "iPhone", "iPad" => "iPad", "Android" => "Android", "Mac OS" => "macOS",
                 "Windows" => "Windows", "Linux" => "Linux" }
      .find { |token, _| agent.include?(token) }&.last

    [ browser, platform ].compact.join(" on ").presence || "Unknown device"
  end
end
