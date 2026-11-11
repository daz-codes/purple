# Be sure to restart your server when you modify this file.
#
# The game never needs device features, so switch them all off.

Rails.application.config.permissions_policy do |policy|
  policy.camera      :none
  policy.microphone  :none
  policy.geolocation :none
  policy.usb         :none
  policy.payment     :none
  policy.gyroscope   :none
  policy.fullscreen  :self
end
