# People, consents and calendar: how the three packs fit together

Three official packs (`people`, `consents`, `calendar`, all 0.1.0) that almost any business that deals with customers needs, and that other packs build on. This page explains the design choices so a pack author or a documentation writer does not have to read the SQL. Per-pack detail is in each pack's `docs/README.md` and `docs/SECURITY.md`.

## The shape

```
subjects (core)  ──<  ppl_people  ──<  ppl_external_refs
                         ▲   ▲
        optional person_id   optional person_id
                         │   │
                 cn_consents   cal_events  <── service-only feed (cal_upsert_event)
```

- `people` is the base. One row per person a business deals with, whatever they are to the business (`kind` is a lowercase token the business chooses).
- `consents` and `calendar` each have an optional `person_id` that names a `people` row. Both use a **composite foreign key** `(person_id, subject_id)`, so a row can never point at a person from another subject. Erasing a person clears `person_id` and keeps the consent or event.
- Neither `consents` nor `calendar` knows about any pack that depends on them. Later packs depend on these three, never the other way round.

## Decisions and the reasons

| Decision | Why |
|---|---|
| People are their own pack, not a table inside a feature pack | Many features point at a person. A feature pack that owned the table would force every other feature to depend on it. |
| Consents are a separate pack with an append-only ledger | Several features must ask "may I contact or record this person for this purpose?". One shared answer (`cn_has_consent`) beats each feature keeping its own flag. Users can insert and read; there is no update or delete. A withdrawal is a new row, and the latest row for a person and purpose wins. Ordering uses `clock_timestamp()` so rows written in one transaction still order. |
| Consents keep a normalised `person_key` (phone or email) as well as `person_id` | An inbound stop reply knows only a phone number. `cn_withdraw` is a service-role function that records it without a signed-in user, and does nothing for someone who never consented. |
| A person's login is a nullable `user_id` on the person row, not a new pack type | The login is a property of the person. It is set only by `ppl_claim` (single-use token, 7-day expiry, account email must match the person's email) and cleared only by `ppl_unlink_login`. `user_id` has no insert or update grant. |
| "Who looks after this person" is a column, `assigned_to`, validated to belong to the same subject | A hierarchy between staff belongs in the team model. Nothing here needs a general reports-to relation. |
| A person with a login sees only their own row | Staff see all (`has_subject_access`); the person sees `user_id = auth.uid()`. Other packs reuse the rule through `ppl_is_self(person_id)`, so a person sees their own records and nobody else's. |
| `ppl_external_refs` is an always-present generic table, not a conditional column | The schema of a pack must be the same everywhere: one migration, one rollback, one test suite, one export for a buyer. A business that uses an outside CRM gets rows in this table, written by a separate connector pack that requires `people`. One that does not has no rows. |
| Calendar events from other features arrive through a service-only feed | `cal_upsert_event` and `cal_remove_source` are idempotent on `(subject, source, source_ref)`. The calendar never reads another pack's tables, and feed events are read-only to users. |
| Calendar uses FullCalendar, loaded only on the `/calendar` page | The base app has no UI library. The installer has no dependency mechanism for packs, so the four `@fullcalendar/*` packages (6.1.21) are in `app/package.json`. A product repo that copies the base code must carry them too. |
| Event times travel as absolute instants | The browser converts the typed local time to ISO before submit, so the server never guesses a time zone. |

## Install order and removal

`consents` and `calendar` require `people`, so install `people` first. The installer refuses to remove `people` while either is installed. `pack add packs/calendar --app app` also copies the page and writes the registry; `pack remove calendar --app app` undoes both.

## What the packs do not do

They send nothing, know no messaging provider, and hold no payment data. Sending, syncing to an outside system, and any industry-specific records are other packs that require these.
