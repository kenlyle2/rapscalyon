# consents: security notes

- Row-level security on `cn_consents`: users see and insert rows only for subjects they can access (`has_subject_access`). The MFA gate applies.
- Append only: no UPDATE or DELETE grant and no policy for `authenticated`. The `created_by` column must be the caller. Deleting a subject removes its ledger (cascade); there is no purge job, because the ledger is evidence.
- `cn_has_consent` is `SECURITY INVOKER`: it can only read rows the caller is allowed to see, so asking about another user's subject answers false. It is executable by `authenticated`, not by `anon`.
- `cn_withdraw` is `SECURITY DEFINER` with no EXECUTE grant to `anon` or `authenticated`: service role only. The caller supplies the subject, so only trusted server code (an inbound webhook that has matched the sender to a subject) may call it.
- Do not put message bodies, health details or full recordings in `evidence`; put an identifier or a short note. The column is capped at 2,000 characters.
- Legal sufficiency (for example US A2P 10DLC and state recording-consent rules) depends on the wording you show and where you operate. The pack records what happened; it does not decide what is lawful.
