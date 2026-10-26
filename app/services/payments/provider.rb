# The contract every payment provider adapter fulfils. Nothing outside the adapters knows a vendor's vocabulary.
module Payments
  class Provider
    def self.provider_name = name.demodulize.underscore

    # false when the adapter lacks its configuration; the registry then refuses to hand it out
    def self.enabled? = true

    def name = self.class.provider_name

    # Starts a hosted checkout and returns a Payments::Checkout (redirect URL + the provider's session reference).
    # Amount and credits come from `product`, never from the request. `idempotency_key` is Payment#token: asking
    # twice with the same key must not create two charges.
    def create_checkout(user:, product:, success_url:, cancel_url:, idempotency_key:) = raise(NotImplementedError)

    # Verifies the signature BEFORE reading anything else, then returns a Payments::Event.
    # Raises Payments::InvalidSignature when the request is not authentic or too old.
    def parse_webhook(request) = raise(NotImplementedError)

    # Asks the provider to stop the subscription at the end of the paid period (not now: the customer keeps what was
    # paid for). Returns nothing useful: the new state reaches us as a :subscription_updated event, then the end itself
    # as :subscription_canceled, both through the webhook path. Raises Payments::Error when the provider refuses.
    def cancel_subscription(subscription) = raise(NotImplementedError)

    # Takes a scheduled cancellation back while the period still runs. Same contract as cancel_subscription.
    def resume_subscription(subscription) = raise(NotImplementedError)

    # Reconciliation: what does the provider say about a payment we never heard back about? A Payments::Event to
    # apply, or nil when it is unknown or still open.
    def fetch_event(payment) = nil
  end
end
