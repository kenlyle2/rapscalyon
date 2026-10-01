# Item tracker
> One tracked-thing model for any vertical, with an event log the browser cannot rewrite.

## Who it's for
Builders who need to track jobs, listings, leads or anything similar and want one proven foundation instead of a new table design each time.

## What you get
- Typed items with title, link, source and notes, owned by a workspace subject.
- An append-only event log; status history is written by the database, not the client.
- A plan cap on items per subject, archive instead of delete, and row-level security with the MFA gate on every table.

## Works well with
subject-individual, subject-business, item-search, social-posts.

## Under the hood
Class-table inheritance: child packs add a 1:1 table keyed on the item, so each kind keeps real columns and constraints while access rules live in one place.
