# ai-chat (0.1.0)

AI chat conversations as a child of item-tracker: a chat per provider and model with its messages in order, recorded by the server, with an optional core charge per reply in the same transaction. Covers the BuilderKit llamagpt, multillm_chatgpt, deepseek_chat and gemini_chat tables with one shape.

Written against the BuilderKit app's table shape (generated types) and behaviour, with fresh code; no BuilderKit source.

## What is in it
- `cht_chats` (item kind `chat`): functions `cht_check_kind`, `cht_start`
- `cht_messages` (item kind `chat`): functions `cht_append`

Every row is an item (child of `item-tracker`) owned by a subject (a Space in product language). Users read their own rows; every write goes through the functions above. Server-side functions (service role) record results and are idempotent on the external reference.

## Two ways to pay
The pack never decides the ledger. Pickaxe credits (or any outside platform) can stay authoritative: record finished work with `*_record` and no core charge. Where the app generates the result itself, use the core ledger path where the pack offers one (`*_request` charges first and refunds once on failure).


## Replaces in the BuilderKit schema
`llamagpt`, `multillm_chatgpt`, `deepseek_chat`, `gemini_chat` (id, user_id, title, model, chat_history json): all one shape. `provider` says which app the chat came from, `title` is the item title, and each element of `chat_history` becomes a `cht_messages` row in order (role user, assistant or system).

## Not here
Executors, storage (keys only; Cloudflare R2 or core's private bucket), UI, per-user rate limits beyond core's, importer for existing data. Users and subscriptions map onto core `profiles` and core billing and need no pack.

## Origin

The table shapes follow apps listed at https://builderkit.ai/apps and were reconstructed from their database schema and behaviour, with new code and no BuilderKit source. RapScalYon is not affiliated with or endorsed by BuilderKit. Their apps page is a good place to see more products that fit this same schema.
