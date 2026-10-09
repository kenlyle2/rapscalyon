# loops-email

Durable email outbox for [Loops](https://loops.so). Server code (or other packs) calls
`lp_enqueue(profile, event, properties)`; a cron route (`/api/loops-email/cron/send`) calls
`lp_claim_outbox()`, sends each row through the Loops events API, then marks it `sent` or `failed`.
Users manage `lp_preferences` (marketing / product). Events named `marketing.*` are suppressed when opted out;
`unsubscribed_at` (set by the Loops webhook handler via service role) suppresses everything.

The Loops API key lives in the app environment (`LOOPS_API_KEY`), never in the database.

**Transactional emails.** Set `LOOPS_TRANSACTIONAL` to a JSON map of event name to the id of a published Loops transactional email, for example `{"app.welcome":"<id>"}`. Those events are sent as transactional emails (the outbox properties become the email's data variables). Events not in the map are sent as Loops events, as before. The ids belong to your own Loops team and live in the app environment, not in the pack.
Per-plan cap on pending rows: `lp_max_pending` via core `get_plan_limit`.
