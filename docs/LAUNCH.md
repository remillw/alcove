# From demo to real launch

Alcove runs in production at alcove.victoire-digital.fr with test payments. Before charging real money:

## Money
- [ ] Stripe live: activate the account (identity, bank), create a live restricted key, live webhook (same 10 events), `PAYMENTS_PROVIDER=stripe`, sandbox off.
- [ ] Prices and VAT: decide TTC prices per country, Stripe Tax or a fixed 20% rate, invoices.
- [ ] Withdrawal right (EU): explicit waiver checkbox before an immediate digital service, in the checkout flow and the terms.
- [ ] Consumer mediator named in the terms (required for B2C in France).

## Legal and trust
- [ ] Have the terms, privacy policy and AI notice reviewed by a lawyer.
- [ ] Sign Anthropic's data processing addendum; quote its retention period in the privacy policy.
- [ ] Records of processing and a light DPIA (vulnerable users may confide health or intimate topics).
- [ ] Age: decide whether 18+ self-declaration is enough or add stronger checks.

## Product and operations
- [ ] Own domain (alcove.* or another name, after an INPI/USPTO trademark check).
- [ ] SMTP for password reset and welcome emails (SMTP_ADDRESS, SMTP_USERNAME, SMTP_PASSWORD, MAIL_FROM), with SPF/DKIM on the sending domain.
- [ ] VOYAGE_API_KEY for semantic memory recall, then `bin/rails memory:embed` and `memory:eval`.
- [ ] Backups copied off the server (R2), restore test monthly.
- [ ] Error tracking (Sentry) and an uptime alert.
- [ ] Review reports weekly (Hermes `open_reports`), a human moderation routine.
- [ ] Raise LLM_THREADS with Postgres connections in mind (see Load test in the README), PgBouncer beyond ~25 threads.
