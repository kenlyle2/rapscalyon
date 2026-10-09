# chat-with-file (0.1.0)

Chat with a document: the uploaded file's storage key and name attached 1:1 to an ai-chat conversation. Replaces the BuilderKit chat_with_file table.

Written against the BuilderKit app's table shape (generated types) and behaviour, with fresh code; no BuilderKit source.

## What is in it
- `cwf_sources` (item kind `chat`): functions `cwf_attach`

Every row is an item (child of `item-tracker`) owned by a subject (a Space in product language). Users read their own rows; every write goes through the functions above. Server-side functions (service role) record results and are idempotent on the external reference.

## Two ways to pay
The pack never decides the ledger. Pickaxe credits (or any outside platform) can stay authoritative: record finished work with `*_record` and no core charge. Where the app generates the result itself, use the core ledger path where the pack offers one (`*_request` charges first and refunds once on failure).


## Replaces in the BuilderKit schema
`chat_with_file` (id, user_id, file, filename, chat_history): `file` becomes `file_key` (a storage key); `chat_history` lives in ai-chat's `cht_messages`.

## Not here
Executors, storage (keys only; Cloudflare R2 or core's private bucket), UI, per-user rate limits beyond core's, importer for existing data. Users and subscriptions map onto core `profiles` and core billing and need no pack.

## Origin

The table shapes follow apps listed at https://builderkit.ai/apps and were reconstructed from their database schema and behaviour, with new code and no BuilderKit source. RapScalYon is not affiliated with or endorsed by BuilderKit. Their apps page is a good place to see more products that fit this same schema.
