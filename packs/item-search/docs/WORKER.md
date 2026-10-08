# Worker contract for item-search child packs

The matching worker lives outside the database and uses the service role. A child pack's Builder targets this contract: the pack supplies tables and functions, the worker supplies the six stages below. Each stage has a typed input and output so it can be built and tested alone, one prompt and one test per stage.

## Rules for every worker
- Secrets come from the environment only, and are never logged or stored in a table.
- Every stage is idempotent. Re-running a day's work produces the same rows, not duplicates.
- Every run has a budget (maximum paid fetches, model calls and image reads) and stops cleanly when it is reached. Group identical searches across people so a paid fetch happens once.
- Sources are pluggable. A source is a function from a search to raw items; adding one changes no other stage.
- The worker writes only what this contract lists. It never writes user-owned status columns.
- A stage that cannot decide leaves the field null and records why. It does not guess.
- Each run writes a run record: start, end, counts per stage, spend, errors.

## Stages

| # | Stage | Input | Output | Writes |
|---|---|---|---|---|
| 1 | Fetch | the distinct active search profiles (`is_profiles` where `active`) | raw items as `{source, external_id, url, fetched_at, payload}` | the child pack's raw/listing cache (service role) |
| 2 | Normalize | raw items | `NormalizedItem` (below) with prices in one currency using a dated rate; items with no price, or missing a required field, are dropped with a reason | listing cache |
| 3 | Extract | normalized items that survive | structured fields from text and images, each with a `confidence`; null instead of a guess; the list of inferred fields | listing cache |
| 4 | Value | extracted items | `fair_value`, `comparables_n`, `confidence` per `docs/MATCHING.md` section 3 | score table |
| 5 | Score | valued items and each profile's settings | `match_score` and `score` per (item, profile) via the gate-then-blend rule in `docs/MATCHING.md` section 4 | score table |
| 6 | Deliver | eligible scored items | candidate rows for each matching profile | `is_candidates` |

### NormalizedItem
```json
{
  "source": "string",
  "external_id": "string",
  "url": "https://...",
  "title": "string",
  "price": 0,
  "currency": "ISO 4217",
  "price_usd": 0,
  "fx_rate": {"rate": 0, "as_of": "YYYY-MM-DD"},
  "location": {"lat": 0, "lon": 0},
  "images": ["https://..."],
  "text": "string",
  "first_seen": "timestamp",
  "last_seen": "timestamp",
  "fields": {"<name>": {"value": null, "confidence": 0.0, "inferred": false}}
}
```

## Delivery contract (stage 6)
- Insert into `is_candidates` with `profile_id`, `subject_id` (the profile's own subject), `external_ref` (the source plus its external id), `title`, `url`, `source`, and `reason` (an object carrying `score`, `match_score`, `fair_value`, `confidence` for display). Conflicts on `(profile_id, external_ref)` are ignored, so re-delivery is safe.
- Never deliver an item the person blocked, an item the data rules reject, or an item whose rejection gap has not been exceeded. The child pack enforces these with constraints so a worker bug cannot bypass them; the worker also checks them to avoid wasted writes.
- Read the person's actions back through `is_outbox` (`is_claim_outbox`): `candidate.accepted` and `profile.changed` tell the worker when to re-run or stop.
- Review-then-act work (messages sent for the person, for example) goes through `is_dispatches`: insert `pending_review`, wait for approval, then `is_claim_next_dispatch` and `is_complete_dispatch`.

## What a child pack must provide for this contract
- A listing cache keyed by source and external id, writable only by the service role.
- A score table per (item, profile) with the columns stage 4 and 5 write, writable only by the service role.
- Constraints for the data rules (required fields present, blocked items refused, rejection gap).
- A read view or function that ranks a person's candidates without exposing other people's rows.

## Tests the worker owes
- Each stage with recorded sample inputs, including malformed and non-English text.
- A rerun of the same input changes no rows.
- A budget of zero does no paid work.
- A valuation that excludes the item being valued from its own comparables.
