# What every provider's webhook is reduced to. Times are UTC, amounts are integer cents.
#
#   payment_succeeded     a one-off pack was paid            (token, external_id, amount_cents, currency)
#   payment_failed        the payment was declined           (token)
#   payment_expired       the checkout was never completed   (token)
#   payment_refunded      ONE refund went back to the customer (external_id = the payment, refund_id, amount_cents = this
#                         refund only, never a running total: several partial refunds are several events)
#   subscription_paid     first payment or renewal           (token, subscription_id, external_id = invoice, period_*)
#   subscription_past_due a renewal could not be collected   (subscription_id, token for a first payment)
#   subscription_updated  the provider changed the plan's state (subscription_id, cancel_at_period_end: true once an end
#                         is scheduled for the period's close, false again after a resume)
#   subscription_canceled the subscription ended             (subscription_id)
#   ignored               valid but irrelevant to us
#
# `token` is our own Payment#token, echoed back by the provider; `external_id` is the provider's payment reference.
module Payments
  Event = Data.define(:provider, :id, :type, :token, :external_id, :subscription_id, :amount_cents, :currency, :period_start, :period_end,
    :refund_id, :cancel_at_period_end) do
    def initialize(provider:, id:, type:, token: nil, external_id: nil, subscription_id: nil, amount_cents: nil, currency: nil, period_start: nil, period_end: nil,
      refund_id: nil, cancel_at_period_end: nil) = super
  end
end
