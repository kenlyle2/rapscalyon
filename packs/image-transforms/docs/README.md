# image-transforms (0.1.0)

Image upscale, enhance and style-transfer jobs (BuilderKit image_enhancer_upscaler and ghibli_generation tables) as a child of item-tracker: the input key, the result key and a free-text transform type, charged up front or recorded from an outside generator.

Written against the BuilderKit app's table shape (generated types) and behaviour, with fresh code; no BuilderKit source. Licence check: `docs/DECISIONS.md` in the rapscalyon repo (2026-10-05).

## What is in it
- `itr_jobs` (item kind `image_transform`): functions `itr_check_kind`, `itr_request`, `itr_mark_started`, `itr_complete`, `itr_fail`, `itr_record`

Every row is an item (child of `item-tracker`) owned by a subject (a Space in product language). Users read their own rows; every write goes through the functions above. Server-side functions (service role) record results and are idempotent on the external reference.

## Two ways to pay
The pack never decides the ledger. Pickaxe credits (or any outside platform) can stay authoritative: record finished work with `*_record` and no core charge. Where the app generates the result itself, use the core ledger path where the pack offers one (`*_request` charges first and refunds once on failure).


## Replaces in the BuilderKit schema
`image_enhancer_upscaler` and `ghibli_generation` (id, user_id, type, input_image, output_image, prediction_id, error): both have the same shape, so one pack covers both with `type` as free text. `input_image` and `output_image` become storage keys (`input_key`, `output_keys`).

## Not here
Executors, storage (keys only; Cloudflare R2 or core's private bucket), UI, per-user rate limits beyond core's, importer for existing data. Users and subscriptions map onto core `profiles` and core billing and need no pack.

## Origin

The table shapes follow apps listed at https://builderkit.ai/apps and were reconstructed from their database schema and behaviour, with new code and no BuilderKit source. RapScalYon is not affiliated with or endorsed by BuilderKit. Their apps page is a good place to see more products that fit this same schema.
