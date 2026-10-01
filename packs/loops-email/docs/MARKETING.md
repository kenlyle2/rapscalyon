# Email with Loops
> A reliable outbox for lifecycle and transactional email, with unsubscribes respected automatically.

## Who it's for
Anyone using Loops who wants emails sent exactly once and users in control of what they receive.

## What you get
- `lp_enqueue` from any server code; a cron route drains the outbox into Loops with retries.
- Marketing versus product preferences per user, with a settings page included.
- Suppression of marketing events for opted-out users, enforced in the database.

## Works well with
every pack that emits events: item-tracker, social-posts.

## Under the hood
Rows are claimed with `FOR UPDATE SKIP LOCKED`, sent with an idempotency key, and visible to their recipient only. The Loops key never touches the database.
