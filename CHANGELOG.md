# Changelog

Versioning: core + shell share the repo version (semver, pre-1.0: minor bumps may break). Each pack versions itself in `pack.toml`.

## Unreleased
- `billing-webhook` pack moved into core (migration `core_billing`, route, admin page, `docs/BILLING.md`); `rapscalyon.py core` applies it idempotently.
- Added `AGENTS.md` (working policy).
- New AGPL base packs: `item-tracker`, `item-search` (generic item/search model; child packs add typed kinds).
- Installer: `tier = "commercial"` packs (`license = "LicenseRef-..."`) and `RAPSCALYON_PACKS_PATH` for packs distributed outside this repo.
- `jobs-tracker` moved out to the private commercial `rapscalyon-plus` repo (0.2.0 is a child of `item-tracker`).
- New AGPL pack `invoice-refunds` 0.1.0: customers, invoices, lines, refunds with money rules enforced by triggers (refund only against a paid invoice, never beyond what remains, owner-only approval, outbox event); `rules/declare_logic.py` holds the same rules in GenAI-Logic form (run and proven in LogicBank on SQLite: 12 scenarios mirror the SQL tests).
- Pickaxe Interviewer: GenAI-Logic docs attached, role Step 3B captures business rules as requirements for the hand-off ticket (GenAI-Logic is the planned rules target, not yet generated).

## 0.5.0 — 2026-10-01 — first complete, tested release (pre-1.0)

- Core: RLS-everywhere, default-deny grants, MFA gate, subjects/limits/pricing, private `media` bucket.
- 10 official packs (AGPL-3.0-or-later): subject-individual, subject-business, team, real-estate-listings, jobs-tracker, social-posts, loops-email, turnstile, posthog-analytics, billing-webhook.
- Next.js 15 shell with pack-installed UI/API routes; generic `/api/billing-webhook` (WooCommerce/WPSubscription, FluentCart, or any caller).
- Pickaxe interviewer artifacts (role prompt, OpenAPI action, platform KB).
- Installer/validator, `deploy.sh`, Dockerfile, demo-matrix tooling.
- Verified on 8 hosted demo instances (all suites green, identical core fingerprint) plus Playwright UI e2e.

Not yet: CLA text, trademark, FluentCart field verification, JobsGlider baseline migration, Tier-2 KB docs. See `docs/DECISIONS.md`.
