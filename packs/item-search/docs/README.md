# item-search
Three layers on top of `item-tracker`:
1. **Profiles** (`is_profiles`): a saved search per subject, with a `kind` (what it looks for), `criteria` (a JSON array of groups) and `exclusions`.
2. **Candidates** (`is_candidates`): items proposed for a profile by an *external matcher* using the service role. A user accepts one
   (`is_accept_candidate` creates the `it_items` row) or dismisses it. Re-delivery is safe: `unique (profile_id, external_ref)`.
3. **Dispatches** (`is_dispatches`): a review-then-act queue. A service inserts `pending_review` with a `payload`; the user may set `overrides`, then
   approves (optionally delayed) or cancels. A *worker* calls `is_claim_next_dispatch()` and then `is_complete_dispatch(id, ok, error)`.

`is_outbox` is a poll-based hook: `profile.changed`, `candidate.accepted` and `dispatch.approved` events for the matcher and worker (`is_claim_outbox`).
There is no `pg_net` or vault dependency; the pack never calls out to anything.

This pack deliberately contains no matching, ranking, scraping or submission logic. Plug those in as separate services that use the service role.
Child packs add typed columns keyed on `is_profiles` (see `jobs-search`).
