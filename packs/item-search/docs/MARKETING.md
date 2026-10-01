# Item search
> Saved searches, a review inbox and a safe worker queue, with your matcher plugged in from outside.

## Who it's for
Products that find things for people (jobs, listings, leads) and want the user to approve before anything is acted on in their name.

## What you get
- Saved search profiles per workspace with flexible criteria and exclusions, capped by plan.
- A candidate inbox: accept to create a tracked item, or dismiss, with duplicate-safe delivery from any matcher.
- A review-then-dispatch queue: edit overrides, approve with an optional delay, or cancel; workers claim each job exactly once.
- A poll-based event outbox so matchers and workers know when to run. No webhooks or stored secrets inside the database.

## Works well with
item-tracker, loops-email (commercial child: jobs-search).

## Under the hood
Every user action is a function that checks the caller, the workspace and the MFA gate. The queue contract is three service-role functions, and the pack contains no matching or submission logic.
