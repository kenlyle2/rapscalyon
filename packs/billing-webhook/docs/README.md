# billing-webhook

Provider-agnostic subscription sync. A webhook route in the app (one small adapter per provider: FluentCart,
WooCommerce Subscriptions, Stripe, ...) verifies the provider signature, normalizes the payload to
`(source, external_id, kind, customer_ref, subscription_ref, plan_key, email, occurred_at)` and calls
`bw_apply_event` with the service role. Core's `billing_events` table is the ledger; this pack adds plan mapping
(`bw_plan_map`: provider plan key -> tier) and the application logic.

Kinds: activated, renewed, payment_failed (keeps access, marks past_due), canceled (keeps access until expiry),
expired and refunded (drop to `free`). Results: applied, duplicate, stale, unmatched, unmapped_plan.
Unmatched/unmapped events are kept (status `partial`) and counted by the `bw_unmatched_events` health check.
