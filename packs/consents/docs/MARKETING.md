# Consent ledger
> Record who said yes, who said stop, and exactly what they were shown.

## Who it's for
Anyone who messages customers or records sessions and has to prove permission: studios, clinics, tutors, agencies.

## What you get
- Grants and withdrawals kept as an append-only history, never overwritten.
- A one-call check that answers "may I contact this person about this?".
- A safe way for an inbound STOP reply to withdraw consent without a signed-in user.
- The wording version and a short note of evidence on every row.

## Works well with
people, subject-business, team, loops-email, social-posts.

## Under the hood
One ledger table with row-level security and no edit or delete rights for users. The latest row per person and purpose decides. Withdrawals from outside a session go through a service-role function.
