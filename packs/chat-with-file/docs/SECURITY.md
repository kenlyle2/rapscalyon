# Security: chat-with-file

- Clients can only read rows of their own subjects (row-level security through `has_subject_access`, plus the MFA gate). No client write grants exist on any table; writes go through SECURITY DEFINER functions with an empty search path.
- Executor and record functions are service role only (execute revoked from public, anon and authenticated), tested.
- Every record call checks that the user owns or is an accepted member of the subject, and is idempotent on an external reference.
- File and result fields hold storage keys (character allow-list, no `..`), never URLs or data URLs. Result URLs from generators expire; copy before recording.
- No provider secret or token is stored. Webhook signatures are the executor's job; the database makes every step idempotent.
- Known gaps: executor and storage policies not written, no per-subject rate limits beyond core's, not tested against real data.
