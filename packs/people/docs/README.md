# People

One row per person a business deals with: clients, former clients, leads, referrers. Other packs point at a person instead of storing a name or a phone number of their own.

## Tables
- `ppl_people`: name, optional email and phone, `kind` (a lowercase token you choose: `client`, `lead`, `former_client`...), `status` (`active`, `inactive`, `archived`), `assigned_to` (the owner or member who looks after them), `notes`, and `user_id` (the person's own login, if they have one).
- `ppl_claims`: one-time invitations that attach a login. No user can read it.
- `ppl_external_refs`: the id a person has in an outside system, if any.

## Who sees what
Staff of the subject (owner and accepted members) see and edit every person. A person with a login sees only their own row. Other packs reuse the same rule with `public.ppl_is_self(person_id)` in their policies, so a client sees their own records and nobody else's.

## Giving a person a login
1. Staff add the person with their email.
2. `select public.ppl_invite_login(person_id)` returns a one-time token; put it in a link.
3. The person signs in and calls `select public.ppl_claim(token)`. Their account email must match the email on the row.
4. `ppl_unlink_login(person_id)` detaches it again; the person row stays.

## Who looks after whom
`assigned_to` is a single staff member of the same subject (enforced). Anything richer, such as a team lead, is a relation between staff and belongs in the team model, not here.

## Outside systems
`ppl_external_refs` records where a person also exists in an outside system, as `system` (a lowercase token you choose, such as `crm`) and `external_id`. One reference per person and system, and an external id belongs to one person. A business that uses no outside system has no rows. A connector pack requires `people`, does the syncing, and writes here.
