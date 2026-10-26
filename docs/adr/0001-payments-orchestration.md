# 0001. Payments behind a provider-agnostic layer

Status: accepted, 2026-10-26

## Context

Alcove sells credits (two packs, one monthly plan). Payment providers differ in vocabulary, fees, coverage and reliability, and a business that depends on one of them has to be able to add or swap another. Whatever the provider, the same things must hold: a customer is never charged twice for one purchase, never credited twice, and a lost notification must not lose a sale.

## Decision

- **One interface, normalised events.** `Payments::Provider` (`create_checkout`, `parse_webhook`, `fetch_event`, `cancel_subscription`, `resume_subscription`) is the only thing the app calls. Adapters translate their vendor's webhooks into `Payments::Event`; `Payments::Settlement` applies events to `Payment`, `Subscription` and the credits ledger and knows no vendor. Provider chosen by `PAYMENTS_PROVIDER`, adapters listed in `Payments::Registry`.
- **The webhook is the source of truth for money, the redirect is not.** Returning to the success URL grants nothing; credits arrive with the signed webhook. A nightly `ReconcilePaymentsJob` asks the provider about payments pending for over an hour, so a lost webhook is caught up through the same `Settlement`.
- **Exactly-once by three layers.** Unique `(provider, event_id)` on `webhook_events`, inserted in the transaction that applies the effects (a failure rolls it back, so the provider's retry is processed). Guarded status transitions. Idempotency keys on every ledger entry (`payment:<provider>:<id>`, `subscription:<id>:<period_start>`), which also protects the reconciliation racing a webhook.
- **The catalogue lives in code; the browser sends a product key.** Amount and credits are copied to the `Payment` before the provider is called. A charge that differs credits nothing and is reported.
- **Money wins.** A "paid" event settles a payment even if it was failed or expired meanwhile (a retry in another tab, a late webhook); a "failed" never overturns a paid one.
- **Refunds are per refund, pro rata, and clamp at zero.** One `payment_refunded` event per provider refund (`refund_id`, `amount_cents` of that refund only). Credits taken back = `credits * refunded_cents / amount_cents`, rounded half up on the cumulative total, so successive partial refunds sum exactly and the last one lands on `credits`; refunds beyond the amount charged are cut and reported. The refund id is kept on the payment and is the ledger key, so any number of events about one refund count once. `Credits.post!(clamp: true)` keeps the balance at zero (credits already spent are not recovered, the shortfall is recorded). Status: `paid`, `partially_refunded`, `refunded`.
- **Cancelling is a request, not a state change.** The button asks the provider to stop at the period's end; the mirror (`cancel_at_period_end`, then `canceled`) follows the provider's events through the same webhook path, so a cancellation made in the provider's dashboard behaves identically. The sandbox plays the provider with signed events; its refund and end-of-period tools are rake tasks, not routes.
- **The sandbox delivers its webhooks in-process, not over HTTP.** It builds the exact signed request a provider would send and passes it to `Payments::Webhooks.receive`, the code path of the real endpoint, signature check included. A loopback HTTP call would need a public host behind HAProxy, a live server in every test, and a Puma thread waiting on itself; the only thing skipped is the network hop. Its checkout state is a signed, expiring token, so the "provider" keeps no table of its own.

## Consequences

- Adding a provider is one adapter, one registry line, and fixtures of its recorded events.
- The default is the sandbox: anyone can "pay" with test money and get credits. That is right for a demo and wrong for production money; `PAYMENTS_PROVIDER=stripe` is the switch.
- Known gaps: refunds of subscription invoices are not matched to their payment (Stripe's charge does not carry the invoice id in recent API versions); webhook ordering is tolerated (renewals never move a period backwards, a canceled subscription stays canceled) but not enforced, so two `customer.subscription.updated` events delivered out of order could leave a stale cancel flag until the next one; a pending or failed Stripe refund is ignored until `refund.updated` says it succeeded; several providers at once means one `PAYMENTS_PROVIDER` for new checkouts, while webhooks and reconciliation route by the provider stored on each payment.
