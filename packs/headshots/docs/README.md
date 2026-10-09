# headshots (0.1.0)

AI headshots as two children of item-tracker (BuilderKit headshot_models and headshot_generations): train a personal model from uploaded photos, then generate headshots from a finished model of the same workspace, charged up front or recorded from an outside generator.

Written against the BuilderKit app's table shape (generated types) and behaviour, with fresh code; no BuilderKit source.

## What is in it
- `hsh_models` (item kind `headshot_model`): functions `hsh_model_check_kind`, `hsh_model_request`, `hsh_model_mark_started`, `hsh_model_complete`, `hsh_model_fail`, `hsh_model_record`
- `hsh_generations` (item kind `headshot`): functions `hsh_gen_check_kind`, `hsh_gen_request`, `hsh_gen_mark_started`, `hsh_gen_complete`, `hsh_gen_fail`, `hsh_gen_record`

Every row is an item (child of `item-tracker`) owned by a subject (a Space in product language). Users read their own rows; every write goes through the functions above. Server-side functions (service role) record results and are idempotent on the external reference.

## Two ways to pay
The pack never decides the ledger. Pickaxe credits (or any outside platform) can stay authoritative: record finished work with `*_record` and no core charge. Where the app generates the result itself, use the core ledger path where the pack offers one (`*_request` charges first and refunds once on failure).


## Replaces in the BuilderKit schema
`headshot_models` (id, user_id, name, type, images[], model_id, status processing|finished, eta, trained_at, expires_at): `images[]` become `input_keys`; `model_id` becomes `model_ref`; status maps queued/processing/succeeded/failed; `trained_at` is `completed_at`; `eta` is not stored (derive it in the UI). `headshot_generations` (id, user_id, model_id, generation_id, prompt, negative_prompt, image_urls[]): `model_id` becomes `model_item` (a real foreign key to a finished model of the same workspace); `generation_id` becomes `prediction_id`.

## Not here
Executors, storage (keys only; Cloudflare R2 or core's private bucket), UI, per-user rate limits beyond core's, importer for existing data. Users and subscriptions map onto core `profiles` and core billing and need no pack.

## Origin

The table shapes follow apps listed at https://builderkit.ai/apps and were reconstructed from their database schema and behaviour, with new code and no BuilderKit source. RapScalYon is not affiliated with or endorsed by BuilderKit. Their apps page is a good place to see more products that fit this same schema.
