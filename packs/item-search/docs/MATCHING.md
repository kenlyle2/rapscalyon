# Matching recipe for item-search child packs

`item-search` ships plumbing, not matching. This is the recipe a child pack and its worker should follow when candidates are ranked by how good a deal they are as well as how well they fit. It was worked out for a used-vehicle finder and applies to any item that has a price, such as vehicles, equipment, rentals, listings or jobs with a salary.

The database enforces rules and holds scores. A worker using the service role fetches, extracts, values and writes scores. Users never write score columns.

## 1. Soft preferences are scored, hard filters are exclusions
- A soft preference (rank of a brand, body type, condition, distance) raises or lowers a score. It never deletes a candidate.
- A setting the person marks NON-NEGOTIABLE is a hard filter: a real exclusion (WHERE clause or constraint), not a large negative score. A penalty can be outweighed by a big discount.
- Structured constraints are plain SQL. Use vector search only for open-ended free text, and not in a first version.

## 2. Fit: `match_score` (0 to 100)
A weighted sum of parts, each scored 0 to 1, with weights that total 100. Starting weights are a guess; tune them against labelled examples (section 6).
- Ranked preference: position in the person's ordered list (for example 1.0, 0.8, 0.6, 0.4, unlisted 0).
- Specification: share of required attributes that match.
- Condition: full credit when the item's condition is among those the person accepts.
- Proximity: 1 minus distance divided by the person's maximum distance.
Count each factor once. If distance is inside `match_score`, do not subtract it again later.

## 3. Value: `undervalue_pct`
`undervalue_pct = (fair_value - price) / fair_value`, with a stated `fair_value` and a confidence.

Fair value from comparables, in order of preference:
1. A licensed price source for the market, if one exists and is paid for.
2. The median of near matches in the pack's own listing cache (same make, model, year band, mileage band, condition).

Rules that keep the comparables honest:
- Exclude the listing being valued, and its duplicates and cross-posts, from its own comparables.
- Asking prices run above sale prices. Say so in the confidence, and calibrate against any sold prices you can get.
- Require a minimum number of comparables. Below it, confidence is low.
- Cold start: with an empty cache every item has low confidence. Seed the cache from a source other than the one being scored, or run an observation period before delivering anything.
- Subtract estimated repair cost from fair value for items the person accepts as projects, so a discounted project is not overrated.
- Store fair value, the number of comparables and the confidence with each score.

## 4. Gate, then blend
Per (item, search profile):
1. **Gate.** Eligible only if it passes every NON-NEGOTIABLE filter, `match_score` is at least the profile's `min_fit`, valuation confidence is not low, and the data rules pass (no price, missing required fields, blocked seller, rejection gap not yet exceeded).
2. **Blend.** Among eligible items:
   `score = value_weight * norm(undervalue_pct) + (1 - value_weight) * norm(match_score)`
   `value_weight` is per profile (0 means fit only, 100 means value only). `norm()` rescales each term to 0 to 1 using fixed bounds (for example `undervalue_pct` clipped to 0 to 50%, `match_score` divided by 100), never the current candidate set, so a score does not change when other items arrive.

The gate keeps a bargain that does not fit from beating a good fit at a fair price. Store `match_score` and `score` so the interface can show why an item ranked where it did.

## 5. Where it runs
- Distance and the fit sum run in Postgres (a function keyed by profile, PostGIS for geography) so thousands of items are never pulled to the app.
- The worker owns fetch, extraction, fair value and writing the score rows. It delivers candidates through the `item-search` service-role contract, which is duplicate-safe on `external_ref`.
- Enforce rules with constraints, triggers and row-level security. Name the writer of every status.

## 6. Evaluate without cheating
- Keep a held-out set of items the owner labels as good or poor deal, blind, before tuning.
- Tune weights and `min_fit` on a different set from the one used to judge them.
- A remembered success story is a test fixture only if it is held out; do not tune until it passes.
- Record every hand-made correction during a build in a ledger. Each one is either automated or declared a human step.
