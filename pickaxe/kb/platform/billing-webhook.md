# Subscription billing sync (billing-webhook)

Connect WordPress and WooCommerce, FluentCart, Stripe or any webhook source to your app's plans.

Tier: official. Version 0.1.0. Provider-agnostic subscription sync (FluentCart, WooCommerce, Stripe, anything that can POST a webhook): idempotent event application onto core profiles, plan-to-tier mapping, stale/out-of-order protection, and an unmatched-event health check.

## Who it's for

Products that sell subscriptions through a store while the app itself runs on Supabase.

## What you get

- One endpoint that understands WooCommerce, WPSubscription and FluentCart events, plus a plain JSON format for anything else.
- Three authentication styles: WooCommerce HMAC signature, hex HMAC, or shared secret header.
- Plan mapping by exact key or by words in the product name, editable in an admin page.
- Idempotent, out-of-order safe, with a ledger of every event and an unmatched-customer health check.

## Works well with

loops-email (welcome and win-back emails), posthog-analytics.

## Under the hood

Tier changes only happen through one server function. Defaults match the PostGlider and JobsGlider policy: cancelled, expired, failed and refunded subscriptions return to free, configurable by an admin.
