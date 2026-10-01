# billing-webhook

Provider-agnostic subscription sync. A webhook route in the app (one small adapter per provider: FluentCart,
WooCommerce Subscriptions, Stripe, ...) verifies the provider signature, normalizes the payload to
`(source, external_id, kind, customer_ref, subscription_ref, plan_key, email, occurred_at)` and calls
`bw_apply_event` with the service role. Core's `billing_events` table is the ledger; this pack adds plan mapping
(`bw_plan_map`: provider plan key -> tier) and the application logic.

Kinds: activated, renewed, payment_failed (keeps access, marks past_due), canceled (keeps access until expiry),
expired and refunded (drop to `free`). Results: applied, duplicate, stale, unmatched, unmapped_plan.
Unmatched/unmapped events are kept (status `partial`) and counted by the `bw_unmatched_events` health check.

## Wiring a store
WordPress + WooCommerce/WPSubscription or FluentCart: use Bit Integrations (or the store's own webhooks) to POST the flat JSON
documented at the top of `server/route.ts` to `https://<your-app>/api/billing-webhook` on subscription create, renew, cancel and
expire. Set `BILLING_WEBHOOK_SECRET` in the app and the same value as the sender's secret/header.
Map products to tiers in `bw_plan_map` (exact plan key, or `contains` to match product names like PostGlider does).
Default policy mirrors PostGlider/JobsGlider: cancelled, expired, failed/on-hold and refunded drop the user to `free`;
set `admin_settings.bw_downgrade_on` (JSON array of kinds) to keep access longer.
