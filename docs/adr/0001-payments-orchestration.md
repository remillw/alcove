# 0001. Payments behind a provider-agnostic layer

Status: accepted, 2026-10-26

## Context

Alcove sells credits (two packs, one monthly plan). Payment providers differ in vocabulary, fees, coverage and reliability, and a business that depends on one of them has to be able to add or swap another. Whatever the provider, the same things must hold: a customer is never charged twice for one purchase, never credited twice, and a lost notification must not lose a sale.

## Decision

- **One interface, normalised events.** `Payments::Provider` (`create_checkout`, `parse_webhook`, `fetch_event`) is the only thing the app calls. Adapters translate their vendor's webhooks into `Payments::Event`; `Payments::Settlement` applies events to `Payment`, `Subscription` and the credits ledger and knows no vendor. Provider chosen by `PAYMENTS_PROVIDER`, adapters listed in `Payments::Registry`.
- **The webhook is the source of truth for money, the redirect is not.** Returning to the success URL grants nothing; credits arrive with the signed webhook. A nightly `ReconcilePaymentsJob` asks the provider about payments pending for over an hour, so a lost webhook is caught up through the same `Settlement`.
- **Exactly-once by three layers.** Unique `(provider, event_id)` on `webhook_events`, inserted in the transaction that applies the effects (a failure rolls it back, so the provider's retry is processed). Guarded status transitions. Idempotency keys on every ledger entry (`payment:<provider>:<id>`, `subscription:<id>:<period_start>`), which also protects the reconciliation racing a webhook.
- **The catalogue lives in code; the browser sends a product key.** Amount and credits are copied to the `Payment` before the provider is called. A charge that differs credits nothing and is reported.
- **Money wins.** A "paid" event settles a payment even if it was failed or expired meanwhile (a retry in another tab, a late webhook); a "failed" never overturns a paid one.
- **Refunds clamp at zero** (`Credits.post!(clamp: true)`): credits already spent are not recovered, the shortfall is recorded in the entry's metadata.
- **The sandbox delivers its webhooks in-process, not over HTTP.** It builds the exact signed request a provider would send and passes it to `Payments::Webhooks.receive`, the code path of the real endpoint, signature check included. A loopback HTTP call would need a public host behind HAProxy, a live server in every test, and a Puma thread waiting on itself; the only thing skipped is the network hop. Its checkout state is a signed, expiring token, so the "provider" keeps no table of its own.

## Consequences

- Adding a provider is one adapter, one registry line, and fixtures of its recorded events.
- The default is the sandbox: anyone can "pay" with test money and get credits. That is right for a demo and wrong for production money; `PAYMENTS_PROVIDER=stripe` is the switch.
- Known gaps: only full refunds take credits back; refunds of subscription invoices are not matched to their payment (Stripe's charge does not carry the invoice id in recent API versions); no cancel button (the provider's portal does it, and `customer.subscription.deleted` reaches us); webhook ordering is tolerated (renewals never move a period backwards) but not enforced; several providers at once means one `PAYMENTS_PROVIDER` for new checkouts, while webhooks and reconciliation route by the provider stored on each payment.
