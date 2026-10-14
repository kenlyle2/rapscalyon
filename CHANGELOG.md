# Changelog

Versioning: core + app base code share the repo version (semver, pre-1.0: minor bumps may break). Each pack versions itself in `pack.toml`.

## Unreleased
- Patch bumps (comments and docs only, no schema change): `headshots`, `image-generations`, `image-transforms`, `music-generations`, `qr-code-generations`, `voice-transcriptions` 0.1.3 and `interior-designs` 0.2.2 no longer name an outside agent platform; the ingest route's external reference prefix is now `agent:` (it was the platform's name; no deployed data is known to carry the old prefix). `tools/rapscalyon.py` header now says AGPL-3.0-or-later (it said GPL). The `Packs` workflow no longer has a push trigger.
- Internal material moved out of this repository: the interview knowledge-base folder, the sign-in pack, the operating manual, the WordPress-side `integrations/` plugins, `docs/AUTH-MODES.md`, `tools/offer_sync`, `tools/menu_import`, the interior-designs agent action file, the pack-builder skill (now gitignored), the interview knowledge-base generation in `catalog`, and the repository's own `AGENTS.md`, `CLAUDE.md` and `SPEC.md` are no longer here (the last three are gitignored), and git history was rewritten to remove them.
- Wording and catalog: no pack counts anywhere; the README groups every pack (adds `places`); `CONTRIBUTING.md` defines Open source, Pro and Commercial and how Pro relates to official, verified and community; cross-references to Pro packs say "a Pro pack" and the dead `items-matching-ranking` reference is removed; the outside AI platform is no longer named in pack docs; Sixteen packs take a patch bump for their changed docs.
- `calendar` 0.2.0: event status `missed`, and `cal_missed_counts(subject, from, to, person)` for misses by kind over a window (migration 002, rollback and suite included).
- New official packs `people` 0.1.0, `consents` 0.1.0 and `calendar` 0.1.0. `people`: one row per person a business deals with (kind, status, assigned staff member), an optional link to the person's own login redeemed with a single-use token, and `ppl_external_refs` for ids in outside systems. `consents`: append-only grant/withdraw ledger with a `cn_has_consent` check and a service-only `cn_withdraw` for inbound STOP replies. `calendar`: events with a month/week/day page and a service-only feed (`cal_upsert_event`, `cal_remove_source`) so other features add read-only events. App base code: `app/package.json` gains `@fullcalendar/*` 6.1.21 (loaded only on `/calendar`).
- Quick start: added the missing `app/.env.local` step (the app returns HTTP 500 without it) and the reduced `supabase start -x ...` command for machines where storage or realtime reports unhealthy. Found by running the quick start end to end against a fresh clone.
- Documentation site (user guide, concepts, installer reference, help center, changelog) published at rapscalyon.documentationai.com from a documentation repository kept outside this one.
- Wording: the paid packs are called Pro packs (`tier = "commercial"` is unchanged); "RapScalYon Commercial" (RC) names only the done-for-you side. `docs/ARCHITECTURE.md` naming rules define both; the word "plus" is retired.
- `PACK-EXCEPTION.md`: AGPL section 7 additional permission. A pack that copies no Program file and uses only the documented pack interfaces is an independent work and may be licensed on any terms. Drafted by the maintainer; counsel review pending.
- `.claude/verify.json` opts this repo into the Starter Kit verify-on-stop hook: `npm --prefix app run typecheck` must pass before an agent session can finish. The kit is a separate user-level Claude Code plugin; nothing in this repo depends on it.
- Installer: `pack add --project <ref>` now also copies the pack's `server/`, `ui/` and `public/` files into `--app` and regenerates the registry (it used to skip this for hosted projects).
- `loops-email` 0.1.1: events named in `LOOPS_TRANSACTIONAL` (JSON event -> transactional id) are sent as Loops transactional emails; others unchanged. Contributed from the CarShopper product, generalised so no team ids live in the pack.
- Installer: refuses a local database that holds tables neither core nor an installed pack declares (`RS_ALLOW_UNREGISTERED=1` overrides); `pack remove` deletes the pack's generated `supabase/migrations` replay files instead of adding a remove file, and install timestamps never collide, so `supabase db reset` rebuilds exactly the installed packs. `bw_plan_map` added to the core-table list. `ci_packs.py` checks both.
- `loops-email` test counts only its own events (other packs' sign-up triggers no longer break it).
- `.agents/skills/pack-builder`: skill for building and changing packs.
- App base code seam: packs may declare `[auth]` in `pack.toml` (`login_path` or `login_env`, `signup`, `public_paths`) and install `public/` routes into `app/(public)`; `/login` and the middleware read it from the generated registry. Default behaviour is unchanged when no pack declares it.
- Agent-facing tooling, stack guidance, billing and stack docs, the operating manual and the `docs-drift` job are no longer in this repo. Earlier history still contains them.
- New `places` pack 0.1.0 (from the CarShopper work): Provincia / Cantón / Distrito / town directory from OpenStreetMap with fuzzy search, place-in-text, nearest-place and km distance; Coto Brus seeded, `tools/load-canton.mjs` loads any canton.
- Public repository is self-contained: no file names a private repository or points into one. Removed the dead "Licence check: `docs/DECISIONS.md`" sentence from 12 BuilderKit-shaped pack READMEs and the generator (their Origin section already states the clean-room basis); commercial-pack mentions in code, docs and comments say "a separate private repo"; `AGENTS.md`, `SPEC.md` and `docs/ARCHITECTURE.md` describe only this repository. Patch bumps to 0.1.1 for the 12 packs and `item-tracker` (docs only, no migration change). `tools/builderkit_packs/gen.py` writes to `$BUILDERKIT_OUT` (default `./out`).
- `item-search` 0.3.0: user-managed lists (`is_lists`, `is_list_items`; create, rename, delete, add, remove through functions that check subject access and MFA). A candidate can be on several lists.
- `item-search` 0.2.0: price history for every kind of item (`is_price_history`, `is_record_price()` for child packs; one row per price change with the price as typed). Migration 002, rollback and suite included.
- Offer sync: DeepSeek adapter (`RSY_LLM=deepseek`, reads images) and ScrapeCreators as the default Facebook source; Graph API docs marked optional.
- `billing-webhook` pack moved into core (migration `core_billing`, route, admin page, `docs/BILLING.md`); `rapscalyon.py core` applies it idempotently.
- New AGPL base packs: `item-tracker`, `item-search` (generic item/search model; child packs add typed kinds).
- Installer: `tier = "commercial"` packs (`license = "LicenseRef-..."`) and `RAPSCALYON_PACKS_PATH` for packs distributed outside this repo.
- `jobs-tracker` moved out to a separate private repo for commercial packs (0.2.0 is a child of `item-tracker`).
- New AGPL pack `invoice-refunds` 0.1.0: customers, invoices, lines, refunds with money rules enforced by triggers (refund only against a paid invoice, never beyond what remains, owner-only approval, outbox event); `rules/declare_logic.py` holds the same rules in GenAI-Logic form (run and proven in LogicBank on SQLite: 12 scenarios mirror the SQL tests).

## 0.5.0 — 2026-10-01 — first complete, tested release (pre-1.0)

- Core: RLS-everywhere, default-deny grants, MFA gate, subjects/limits/pricing, private `media` bucket.
- 10 official packs (AGPL-3.0-or-later): subject-individual, subject-business, team, real-estate-listings, jobs-tracker, social-posts, loops-email, turnstile, posthog-analytics, billing-webhook.
- Next.js 15 app base code with pack-installed UI/API routes; generic `/api/billing-webhook` (WooCommerce, a store plugin, or any caller).
- Installer/validator, `deploy.sh`, Dockerfile, demo-matrix tooling.
- Verified on 8 hosted demo instances (all suites green, identical core fingerprint) plus Playwright UI e2e.

Not yet: CLA text, trademark, store field verification, Tier-2 KB docs.
