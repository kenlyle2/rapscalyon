# music-generations (0.1.0)

Text-to-music generation jobs (the BuilderKit music_generations table) as a child of item-tracker: prompt, genre, mood, duration and an audio key, charged up front or recorded from an outside generator.

Written against the BuilderKit app's table shape (generated types) and behaviour, with fresh code; no BuilderKit source.

## What is in it
- `mgn_tracks` (item kind `music_track`): functions `mgn_check_kind`, `mgn_request`, `mgn_mark_started`, `mgn_complete`, `mgn_fail`, `mgn_record`

Every row is an item (child of `item-tracker`) owned by a subject (a Space in product language). Users read their own rows; every write goes through the functions above. Server-side functions (service role) record results and are idempotent on the external reference.

## Two ways to pay
The pack never decides the ledger. Pickaxe credits (or any outside platform) can stay authoritative: record finished work with `*_record` and no core charge. Where the app generates the result itself, use the core ledger path where the pack offers one (`*_request` charges first and refunds once on failure).


## Replaces in the BuilderKit schema
`music_generations` (id, user_id, prompt, genre, mood, duration, music_url, prediction_id, error): `music_url` becomes `output_keys` (one storage key); duration is a bounded integer (seconds).

## Not here
Executors, storage (keys only; Cloudflare R2 or core's private bucket), UI, per-user rate limits beyond core's, importer for existing data. Users and subscriptions map onto core `profiles` and core billing and need no pack.

## Origin

The table shapes follow apps listed at https://builderkit.ai/apps and were reconstructed from their database schema and behaviour, with new code and no BuilderKit source. RapScalYon is not affiliated with or endorsed by BuilderKit. Their apps page is a good place to see more products that fit this same schema.
