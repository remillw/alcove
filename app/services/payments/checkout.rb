# What a provider returns when asked to start a checkout: where to send the customer, and the provider's own reference
# for the session (kept on the Payment so reconciliation can ask about it later).
module Payments
  Checkout = Data.define(:url, :reference) do
    def initialize(url:, reference: nil) = super
  end
end
