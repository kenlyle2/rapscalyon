# Changelog

Versioning: core + app base code share the repo version (semver, pre-1.0: minor bumps may break). Each pack versions itself in `pack.toml`.

## Unreleased
- Pickaxe KB `vertical-hostinger-node-hosting`: adds the WordPress site for account mode B and a labelled note on the Hostinger AI Agent. Republished (document id changed).
- `docs/AUTH-MODES.md`: Hostinger section for creating the Mode B WordPress site (API operations, polling, what is unverified) and an honest AI Agent note.
- Pickaxe KB: `vertical-wordpress-multisite` removed (multisite dropped as a billing-site strategy, owner decision 2026-10-09). Detached from the Interviewer and deleted from the workspace.
- Pickaxe KB `vertical-affiliatewp`: states RapScalYon's unlimited-site Ultimate licence, and that nothing installs AffiliateWP on client sites yet. Republished (document id changed); live Interviewer answers correctly.
- Interviewer: the AffiliateWP line no longer says it is installed for the client (nothing installs it yet); it states that our unlimited-site licence covers client sites. `docs/ARCHITECTURE.md` gains "Third-party licences we hold".
- `loops-email` 0.1.1: events named in `LOOPS_TRANSACTIONAL` (JSON event -> transactional id) are sent as Loops transactional emails; others unchanged. Contributed from the CarShopper product, generalised so no team ids live in the pack.
- Interviewer (`propose_stack`): new answers `wants_store`, `wants_affiliates`, `account_mode` (`app`|`wordpress`); the response carries `auth` (mode, decided, why). Selling or affiliates adds FluentCart/AffiliateWP as external products; `wp-fluentauth`, FluentAuth and `rapscalyon-pseudo-sso` are proposed only when the person chose WordPress. `confirm_stack` tickets point at `docs/AUTH-MODES.md` for mode B. Test: `app/e2e/interview.e2e.mjs`.
- Installer: refuses a local database that holds tables neither core nor an installed pack declares (`RS_ALLOW_UNREGISTERED=1` overrides); `pack remove` deletes the pack's generated `supabase/migrations` replay files instead of adding a remove file, and install timestamps never collide, so `supabase db reset` rebuilds exactly the installed packs. `bw_plan_map` added to the core-table list. `ci_packs.py` checks both.
- `loops-email` test counts only its own events (other packs' sign-up triggers no longer break it).
- `.agents/skills/pack-builder`: skill for building and changing packs.
- `docs/AUTH-MODES.md`: choose, install, verify and roll back for account mode A (app accounts) and B (WordPress accounts); linked from README and BILLING.
- Account mode B: new official pack `wp-fluentauth` 0.1.0 (WordPress/FluentAuth owns sign-up, login, recovery and MFA; handoff log `wf_handoffs`) and WordPress plugin `integrations/rapscalyon-pseudo-sso` (about 40 lines; replaces SupaWP for this mode) with an idempotent `install-wordpress.sh --dry-run`. App base code seam: packs may declare `[auth]` in `pack.toml` (`login_path` or `login_env`, `signup`, `public_paths`) and install `public/` routes into `app/(public)`; `/login` and the middleware read it from the generated registry. Default behaviour is unchanged when no pack declares it.
- `item-search` 0.3.0: user-managed lists (`is_lists`, `is_list_items`; create, rename, delete, add, remove through functions that check subject access and MFA). A candidate can be on several lists.
- `item-search` 0.2.0: price history for every kind of item (`is_price_history`, `is_record_price()` for child packs; one row per price change with the price as typed). Migration 002, rollback and suite included.
- Offer sync: DeepSeek adapter (`RSY_LLM=deepseek`, reads images) and ScrapeCreators as the default Facebook source; Graph API docs marked optional.
- Offer synchronizer: Facebook posts become FluentCart offer drafts a shopkeeper approves with one tap. New `integrations/fluentcart-schedule` (weekday, time and date availability, enforced at every purchase path), `integrations/fluentcart-offers` (REST receiver, signed approval links, public active-offers feed), `integrations/offers-widget` (`<rsy-offers>`), and `tools/offer_sync` (Graph API and ScrapeCreators sources, Spanish extractor, stdlib runner).
- ClawMagic.ai adopted as the opinionated destination/executor; `confirm_stack` now returns `executor` and a paste-ready `ticket`; Pickaxe roles hand off to ClawMagic.
- `billing-webhook` pack moved into core (migration `core_billing`, route, admin page, `docs/BILLING.md`); `rapscalyon.py core` applies it idempotently.
- New AGPL base packs: `item-tracker`, `item-search` (generic item/search model; child packs add typed kinds).
- Installer: `tier = "commercial"` packs (`license = "LicenseRef-..."`) and `RAPSCALYON_PACKS_PATH` for packs distributed outside this repo.
- `jobs-tracker` moved out to the private commercial `rapscalyon-plus` repo (0.2.0 is a child of `item-tracker`).
- New AGPL pack `invoice-refunds` 0.1.0: customers, invoices, lines, refunds with money rules enforced by triggers (refund only against a paid invoice, never beyond what remains, owner-only approval, outbox event); `rules/declare_logic.py` holds the same rules in GenAI-Logic form (run and proven in LogicBank on SQLite: 12 scenarios mirror the SQL tests).
- Interviewer needs mapping: crm, contacts, sales-pipeline, booking, scheduling, automations, follow-ups, client-portal, customer-portal, quotes and e-signature map to NinjaPipe as `external` (buy, don't build, never a pack); needs that match nothing come back as `unmatched` instead of being dropped silently.
- Pickaxe Interviewer: GenAI-Logic docs attached, role Step 3B captures business rules as requirements for the hand-off ticket (GenAI-Logic is the planned rules target, not yet generated).

## 0.5.0 — 2026-10-01 — first complete, tested release (pre-1.0)

- Core: RLS-everywhere, default-deny grants, MFA gate, subjects/limits/pricing, private `media` bucket.
- 10 official packs (AGPL-3.0-or-later): subject-individual, subject-business, team, real-estate-listings, jobs-tracker, social-posts, loops-email, turnstile, posthog-analytics, billing-webhook.
- Next.js 15 app base code with pack-installed UI/API routes; generic `/api/billing-webhook` (WooCommerce/WPSubscription, FluentCart, or any caller).
- Pickaxe interviewer artifacts (role prompt, OpenAPI action, platform KB).
- Installer/validator, `deploy.sh`, Dockerfile, demo-matrix tooling.
- Verified on 8 hosted demo instances (all suites green, identical core fingerprint) plus Playwright UI e2e.

Not yet: CLA text, trademark, FluentCart field verification, JobsGlider baseline migration, Tier-2 KB docs.
