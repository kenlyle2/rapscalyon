# interior-designs (0.1.0)

AI room redesigns on RapScalYon core, as a child of `item-tracker`. This replaces the BuilderKit interior-design app's `interior_designs` table: a design is an **item** a subject owns (kind `interior_design`), not a subject.

## Two ways in
1. **Core ledger (we generate).** Client calls `idg_request_design(subject, prompt, room_type, theme, ref_image_key)`; credits are charged first, and a failed charge creates nothing. The executor (service role) calls the model, then `idg_mark_started`; the signature-checked webhook calls `idg_complete` or `idg_fail` (refunds once). Replays are no-ops.
2. **External generator (someone else's ledger).** For the end-user version, the Pickaxe ArtVerve workspace generates the image and bills in Pickaxe credits. A thin API we host copies the image into our own storage (Pickaxe result URLs expire after 2 hours) and calls `idg_record_design(subject, user, external_ref, prompt, room_type, theme, ref_image_key, image_keys)` as service role. No core charge; idempotent on `external_ref`. Never use both paths for one design.

## Not here yet
The executor and webhook route, the ingest API, storage (Cloudflare R2 recommended), per-user authentication of Pickaxe calls (unverified), the UI, and the core credit price for `idg.generate` (defaults to 1).


## Ingest API (0.2.0): saving designs made by a Pickaxe agent

Route `POST /api/interior-designs/ingest`, installed into the app from `server/` by `pack add --app`. A custom Python Pickaxe action (`pickaxe/save_design.action.yaml`) calls it. Credits are never touched on this path: Pickaxe credits are the ledger (owner decision, 2026-10-05).

1. The action sends the signed-in user's email and identifier (from Pickaxe's runtime, not model text), the Pickaxe response id, the prompt, room, style, the result image links and optionally the reference photo link and a Space name, with a shared secret in `x-ingest-secret`.
2. Guests (`API_GUEST:` identifiers or an empty email) are refused (403).
3. The email must belong to a confirmed account (`idg_resolve_user`). An unknown or unconfirmed email is refused (404 `no_account`); **an account is never created here**. Accounts come from WordPress registration (SupaWP).
4. The user's Space is found or created on first use (`idg_ensure_subject`): the named Space, else the oldest Space the user owns, else a new one called "My designs". Plan limits apply (409 `space_limit`).
5. The images are downloaded (https only, allowed hosts only, 12 MB cap, no redirects, type checked from the bytes) and stored in Cloudflare R2 under private keys; result links expire after 2 hours.
6. `idg_record_design` stores the design, idempotent on the response id, so a retried call returns the same design.

Environment: `IDG_INGEST_SECRET`, `IDG_SOURCE_HOSTS` (default `cdn.mail.studio`), `R2_ACCOUNT_ID`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, `R2_BUCKET`, plus the app's Supabase service-role variables. None belongs in a repo.

Words: see `docs/VOCABULARY.md` in the rapscalyon repo. Users see "Space" and "Design", never "subject" or "item".

Tests: `rapscalyon.py test --pack interior-designs` (database) and `node --test tests/ingest.test.ts` (request checks, image sniffing, key shape, and R2 request signing against AWS's published example). Not yet exercised against the real Pickaxe CDN or R2.

## Origin

The table shapes follow apps listed at https://builderkit.ai/apps and were reconstructed from their database schema and behaviour, with new code and no BuilderKit source. RapScalYon is not affiliated with or endorsed by BuilderKit. Their apps page is a good place to see more products that fit this same schema.
