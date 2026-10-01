- Candidates and dispatches are written only by the service role. Users can read them and act through five functions, each of which checks the caller,
  subject access and the MFA gate itself (they are SECURITY DEFINER, so row policies do not apply inside them).
- Users cannot set a dispatch to `approved`, `claimed` or `done` by updating the table; there is no UPDATE grant. Overrides can change only while `pending_review`.
- `is_claim_next_dispatch`, `is_complete_dispatch` and `is_claim_outbox` are SECURITY INVOKER and not granted to API roles: only the service role can run them.
- Claims are exactly-once (`for update skip locked`); stale claims are retried after 10 minutes and abandoned after 5 attempts.
- `is_outbox` has RLS on, no policy and no grant: service role only. The profile cap (`is_max_profiles`) applies only when `auth.uid()` is set.
