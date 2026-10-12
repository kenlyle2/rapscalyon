# People: security notes

- Row-level security on both tables; anon has no privileges.
- Staff access follows `has_subject_access`. A person's own row is also readable by the login attached to it, and by nobody else.
- `user_id` has no insert or update grant. It changes only through `ppl_claim` (the signed-in person, token plus matching account email, single use, 7-day expiry) and `ppl_unlink_login` (staff).
- `ppl_claims` has no policies and no grants: tokens are bearer credentials and are never readable. `ppl_invite_login` returns the token only to staff.
- `assigned_to` is validated by a trigger so a person cannot be assigned to someone outside the subject.
- A person with a login cannot edit, delete or add anyone, including themselves.
- Personal data: names, emails and phone numbers are personal data. Deleting a person row deletes it; tell people how to ask.
- `ppl_external_refs` is readable and writable by staff only; a person with a login never sees outside-system ids. The composite key keeps a reference inside its subject.
