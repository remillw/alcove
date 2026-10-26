# Payment orchestration: the app talks to `Payments::Provider` (an interface), never to a vendor. Providers turn their
# own webhooks into one normalised `Payments::Event`, and `Payments::Settlement` applies it to our tables and to the
# credits ledger. Adding a provider means one adapter class and one line in `Payments::Registry`.
module Payments
  Error = Class.new(StandardError)
  InvalidSignature = Class.new(Error)   # bad, missing or stale signature: the request is rejected (400)
  UnknownProvider = Class.new(Error)
  ProviderUnavailable = Class.new(Error) # known but not configured (e.g. Stripe without its keys)
  UnknownProduct = Class.new(Error)

  def self.provider_name = ENV.fetch("PAYMENTS_PROVIDER", "sandbox")
  def self.provider(name = provider_name) = Registry.fetch(name)
end
