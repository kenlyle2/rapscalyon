# image-generations (0.1.0)

Text-to-image generation jobs (the BuilderKit image_generations table; also the base for the Ghibli-style variant) as a child of item-tracker: prompt, settings and result keys per job, charged up front and refunded once on failure, or recorded from an outside generator.

Written against the BuilderKit app's table shape (generated types) and behaviour, with fresh code; no BuilderKit source. Licence check: `docs/DECISIONS.md` in the rapscalyon repo (2026-10-05).

## What is in it
- `igen_generations` (item kind `image_generation`): functions `igen_check_kind`, `igen_request`, `igen_mark_started`, `igen_complete`, `igen_fail`, `igen_record`

Every row is an item (child of `item-tracker`) owned by a subject (a Space in product language). Users read their own rows; every write goes through the functions above. Server-side functions (service role) record results and are idempotent on the external reference.

## Two ways to pay
The pack never decides the ledger. Pickaxe credits (or any outside platform) can stay authoritative: record finished work with `*_record` and no core charge. Where the app generates the result itself, use the core ledger path where the pack offers one (`*_request` charges first and refunds once on failure).


## Replaces in the BuilderKit schema
`image_generations` (id, user_id, prompt, negative_prompt, model, guidance, inference, no_of_outputs, image_urls[], prediction_id, error): `user_id` becomes the subject and `requested_by`; `image_urls[]` becomes `output_keys` (storage keys); `prediction_id` and `error` keep their meaning; guidance and step counts are typed numbers.

## Not here
Executors, storage (keys only; Cloudflare R2 or core's private bucket), UI, per-user rate limits beyond core's, importer for existing data. Users and subscriptions map onto core `profiles` and core billing and need no pack.

## Origin

The table shapes follow apps listed at https://builderkit.ai/apps and were reconstructed from their database schema and behaviour, with new code and no BuilderKit source. RapScalYon is not affiliated with or endorsed by BuilderKit. Their apps page is a good place to see more products that fit this same schema.
