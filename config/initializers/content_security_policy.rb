# Strict CSP: everything is served from our own origin (fonts are self-hosted, no CDN, no tracker).
Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.font_src    :self
    policy.img_src     :self, :data
    policy.object_src  :none
    policy.script_src  :self
    policy.style_src   :self
    policy.connect_src(*[ :self, ("ws://localhost:*" if Rails.env.development?) ].compact)
    policy.frame_ancestors :none
    policy.base_uri :self
    # a purchase button posts to us, and we answer with a redirect to Stripe's hosted page: form-action covers redirects
    policy.form_action(*[ :self, ("https://checkout.stripe.com" if ENV["STRIPE_SECRET_KEY"].present?) ].compact)
  end
  config.content_security_policy_nonce_generator = ->(request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src style-src]
  config.content_security_policy_nonce_auto = true
end
