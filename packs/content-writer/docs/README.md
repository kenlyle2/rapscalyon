# content-writer (0.1.0)

AI-written content pieces (the BuilderKit content_creations table) as a child of item-tracker: topic, style, voice, word limit and the text, recorded once by the server with an optional core charge in the same transaction.

Written against the BuilderKit app's table shape (generated types) and behaviour, with fresh code; no BuilderKit source. Licence check: `docs/DECISIONS.md` in the rapscalyon repo (2026-10-05).

## What is in it
- `cwr_pieces` (item kind `content_piece`): functions `cwr_check_kind`, `cwr_record`

Every row is an item (child of `item-tracker`) owned by a subject (a Space in product language). Users read their own rows; every write goes through the functions above. Server-side functions (service role) record results and are idempotent on the external reference.

## Two ways to pay
The pack never decides the ledger. Pickaxe credits (or any outside platform) can stay authoritative: record finished work with `*_record` and no core charge. Where the app generates the result itself, use the core ledger path where the pack offers one (`*_request` charges first and refunds once on failure).


## Replaces in the BuilderKit schema
`content_creations` (id, user_id, topic, style, voice, word_limit, results): `word_limit` is a bounded integer instead of a string.

## Not here
Executors, storage (keys only; Cloudflare R2 or core's private bucket), UI, per-user rate limits beyond core's, importer for existing data. Users and subscriptions map onto core `profiles` and core billing and need no pack.

## Origin

The table shapes follow apps listed at https://builderkit.ai/apps and were reconstructed from their database schema and behaviour, with new code and no BuilderKit source. RapScalYon is not affiliated with or endorsed by BuilderKit. Their apps page is a good place to see more products that fit this same schema.
