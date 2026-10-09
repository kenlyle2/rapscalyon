# Changelog

Versioning: core + app base code share the repo version (semver, pre-1.0: minor bumps may break). Each pack versions itself in `pack.toml`.

## Unreleased
- The Pickaxe knowledge-document tooling (`kb_sync.py`, `genai_docs.py`, their workflows and manifest), the vertical stack guidance, `docs/BILLING.md`, `docs/COMMERCE-STACKS.md` and the agent-facing service code are no longer in this repo; `docs/operations.mdx` loses its Pickaxe section and the `docs-drift` job leaves `packs.yml`. Earlier history still contains them.
- New `places` pack 0.1.0 (from the CarShopper work): Provincia / Cantón / Distrito / town directory from OpenStreetMap with fuzzy search, place-in-text, nearest-place and km distance; Coto Brus seeded, `tools/load-canton.mjs` loads any canton.
- Public repository is self-contained: no file names a private repository or points into one. Removed the dead "Licence check: `docs/DECISIONS.md`" sentence from 12 BuilderKit-shaped pack READMEs and the generator (their Origin section already states the clean-room basis); commercial-pack mentions in code, docs and comments say "a separate private repo"; `AGENTS.md`, `SPEC.md` and `docs/ARCHITECTURE.md` describe only this repository. Patch bumps to 0.1.1 for the 12 packs and `item-tracker` (docs only, no migration change). `tools/builderkit_packs/gen.py` writes to `$BUILDERKIT_OUT` (default `./out`).
- `item-search` 0.3.0: user-managed lists (`is_lists`, `is_list_items`; create, rename, delete, add, remove through functions that check subject access and MFA). A candidate can be on several lists.
- `item-search` 0.2.0: price history for every kind of item (`is_price_history`, `is_record_price()` for child packs; one row per price change with the price as typed). Migration 002, rollback and suite included.
- Offer sync: DeepSeek adapter (`RSY_LLM=deepseek`, reads images) and ScrapeCreators as the default Facebook source; Graph API docs marked optional.
- Offer synchronizer: Facebook posts become FluentCart offer drafts a shopkeeper approves with one tap. New `integrations/fluentcart-schedule` (weekday, time and date availability, enforced at every purchase path), `integrations/fluentcart-offers` (REST receiver, signed approval links, public active-offers feed), `integrations/offers-widget` (`<rsy-offers>`), and `tools/offer_sync` (Graph API and ScrapeCreators sources, Spanish extractor, stdlib runner).
- ClawMagic.ai adopted as the opinionated destination/executor; `confirm_stack` now returns `executor` and a paste-ready `ticket`; Pickaxe roles hand off to ClawMagic.
- `billing-webhook` pack moved into core (migration `core_billing`, route, admin page, `docs/BILLING.md`); `rapscalyon.py core` applies it idempotently.
- New AGPL base packs: `item-tracker`, `item-search` (generic item/search model; child packs add typed kinds).
- Installer: `tier = "commercial"` packs (`license = "LicenseRef-..."`) and `RAPSCALYON_PACKS_PATH` for packs distributed outside this repo.
- `jobs-tracker` moved out to a separate private repo for commercial packs (0.2.0 is a child of `item-tracker`).
- New AGPL pack `invoice-refunds` 0.1.0: customers, invoices, lines, refunds with money rules enforced by triggers (refund only against a paid invoice, never beyond what remains, owner-only approval, outbox event); `rules/declare_logic.py` holds the same rules in GenAI-Logic form (run and proven in LogicBank on SQLite: 12 scenarios mirror the SQL tests).

## 0.5.0 — 2026-10-01 — first complete, tested release (pre-1.0)

- Core: RLS-everywhere, default-deny grants, MFA gate, subjects/limits/pricing, private `media` bucket.
- 10 official packs (AGPL-3.0-or-later): subject-individual, subject-business, team, real-estate-listings, jobs-tracker, social-posts, loops-email, turnstile, posthog-analytics, billing-webhook.
- Next.js 15 app base code with pack-installed UI/API routes; generic `/api/billing-webhook` (WooCommerce/WPSubscription, FluentCart, or any caller).
- Installer/validator, `deploy.sh`, Dockerfile, demo-matrix tooling.
- Verified on 8 hosted demo instances (all suites green, identical core fingerprint) plus Playwright UI e2e.

Not yet: CLA text, trademark, FluentCart field verification, JobsGlider baseline migration, Tier-2 KB docs.
