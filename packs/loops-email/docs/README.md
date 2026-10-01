# loops-email

Durable email outbox for [Loops](https://loops.so). Server code (or other packs) calls
`lp_enqueue(profile, event, properties)`; a cron route (`/api/loops-email/cron/send`) calls
`lp_claim_outbox()`, sends each row through the Loops events API, then marks it `sent` or `failed`.
Users manage `lp_preferences` (marketing / product). Events named `marketing.*` are suppressed when opted out;
`unsubscribed_at` (set by the Loops webhook handler via service role) suppresses everything.

The Loops API key lives in the app environment (`LOOPS_API_KEY`), never in the database.
Per-plan cap on pending rows: `lp_max_pending` via core `get_plan_limit`.
