# Changelog

Versioning: core + shell share the repo version (semver, pre-1.0: minor bumps may break). Each pack versions itself in `pack.toml`.

## 0.5.0 — 2026-10-01 — first complete, tested release (pre-1.0)

- Core: RLS-everywhere, default-deny grants, MFA gate, subjects/limits/pricing, private `media` bucket.
- 10 official packs (AGPL-3.0-or-later): subject-individual, subject-business, team, real-estate-listings, jobs-tracker, social-posts, loops-email, turnstile, posthog-analytics, billing-webhook.
- Next.js 15 shell with pack-installed UI/API routes; generic `/api/billing-webhook` (WooCommerce/WPSubscription, FluentCart, or any caller).
- Pickaxe interviewer artifacts (role prompt, OpenAPI action, platform KB).
- Installer/validator, `deploy.sh`, Dockerfile, demo-matrix tooling.
- Verified on 8 hosted demo instances (all suites green, identical core fingerprint) plus Playwright UI e2e.

Not yet: CLA text, trademark, FluentCart field verification, JobsGlider baseline migration, Tier-2 KB docs. See `docs/DECISIONS.md`.
