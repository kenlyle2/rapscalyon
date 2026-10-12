# calendar: security notes

- Row-level security on `cal_events`; anon has no privileges. Everything follows `has_subject_access`.
- Users insert, update and delete only rows with no `source`; the policies and column grants stop a user setting `source` or `source_ref`.
- `cal_upsert_event` and `cal_remove_source` are security definer, service role only (execute revoked from public, anon and authenticated). Callers must pass the subject themselves, so only trusted server code may call them.
- A person link is a composite key, so an event cannot point at a person from another subject.
- Event titles and notes are user text; the page renders them as text, never as HTML.
