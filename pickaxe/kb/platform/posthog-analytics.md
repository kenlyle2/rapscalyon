# Product analytics with PostHog (posthog-analytics)

Product analytics that checks consent first. Users decide what is measured.

Tier: official. Version 0.1.0. PostHog product analytics with privacy controls: per-user analytics/session-replay consent that the app must check before sending any event. Keys stay in the app environment.

## Who it's for

Teams that want PostHog insight without a privacy surprise.

## What you get

- Per-user analytics and session-replay consent, with a privacy settings page.
- A server-side `ph_may_track` gate your code calls before sending events.
- Safe defaults: analytics on, session replay off, replay never without analytics consent.

## Works well with

everything. Particularly useful with jobs-tracker and subject-individual.

## Under the hood

Consent is private to its owner; the gate function is service-role only so users cannot probe each other.
