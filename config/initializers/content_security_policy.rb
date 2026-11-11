# Be sure to restart your server when you modify this file.
#
# Strict Content Security Policy. This is a security training product, so the
# policy is a second line of defence behind the sanitizer that cleans authored
# email bodies on import (see CLAUDE.md, "Security").
#
# - No inline scripts or styles without a per-request nonce.
# - No external hosts at all: every asset is served from our own origin.
# - frame-ancestors 'none' so the app can never be framed (clickjacking).

Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src     :self
    policy.script_src      :self
    policy.style_src       :self
    policy.img_src         :self, :data
    policy.font_src        :self
    policy.connect_src     :self
    policy.object_src      :none
    policy.base_uri        :self
    policy.form_action     :self
    policy.frame_ancestors :none
    policy.frame_src       :none
    policy.worker_src      :self
    policy.manifest_src    :self
  end

  # A fresh random nonce per request for importmap, Turbo and any inline tag.
  config.content_security_policy_nonce_generator = ->(_request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src style-src]
  config.content_security_policy_nonce_auto = true
end
