# RapScalYon SPEC

Status: working draft, 2026-10-01 (v0.5.0). Provenance is marked throughout:
**[user]** stated by the owner, **[repo]** verified in a file named in the text,
**[proposal]** a recommendation that needs the owner's decision. Nothing else is asserted.

## 1. Purpose **[user]**

RapScalYon aims to be the fastest way to build any business app. It is a Next.js shell
plus a Supabase backend, shaped by lessons learned on PostGlider, JobsGlider and TatPlat.
Supabase provides data services and authentication. Business infrastructure is included,
such as Cloudflare Turnstile and Loops.so (business email). Optional **packs** add
functionality on top of the base.

## 2. Architecture **[repo: README.md, supabase/migrations/]**

- **core** (`supabase/migrations/`): profiles, credits and plan limits (`charge_credits`),
  billing-event ledger, rate limiting, **subjects** and `subject_members`, MFA gate,
  `ensure_rls` event trigger, default-deny privileges, private `media` bucket.
- **packs** (`packs/<name>/`): `pack.toml`, `migrations/`, `rollback/`, `tests/`, optional
  `docs/`, `ui/`, `server/`. Each is prefixed, optional, removable, tested, and cannot
  change core. An installer (`tools/rapscalyon.py pack add`) validates and applies each
  pack in one transaction. A pack bundles tables, RLS, grants, functions, extensions
  and cron jobs.
- **app** (`app/`): Next.js shell with a nav built from installed packs.
- Official (AGPL) packs today: `subject-individual`, `subject-business`, `team`,
  `real-estate-listings`, `item-tracker`, `item-search`, `social-posts`, `loops-email`, `turnstile`,
  `posthog-analytics`.

### The "subjects" table

The owner's brief called this table "objects". **In the repo it is `subjects`**
(`core_foundation.sql:246-267`): "the generic thing the user's data hangs off (persona,
business location, ...)". Access goes through `has_subject_access(subject_id)` in every
pack policy. A subject is a TatPlat business profile, a JobsGlider persona
("job search"), and so on. **[proposal]** If "objects" is the intended public name, rename
in core in the same change as every downstream reference. JobsGlider AGENTS.md rule 7
forbids leaving a wrong name in place.

## 3. Item model **[repo: packs/item-tracker, packs/item-search]**

The base packs are generic: a **subject** owns **items** (`item-tracker`) and saved searches with a
review queue (`item-search`). A specific kind of item is a **child pack** that keys 1:1 on the base
table and adds typed columns (class-table inheritance, kind enforced by a trigger). "Item" is used
instead of "object" to avoid Supabase's `storage.objects`. `subjects` keeps its name (owner decision).
Child packs, including the commercial job packs, are distributed separately; see `docs/DECISIONS.md`.

## 3b. Destination **[user]**

ClawMagic.ai is the opinionated destination for clients, users and builders: Pickaxe designs, ClawMagic executes
and operates. Details, provenance and the unverified parts are in `docs/CLAWMAGIC.md`.

## 4. Licensing model **[user, proposal]**

Open core: the core, the base packs and the installer are AGPL-3.0-or-later. "Plus" packs are
commercial (`tier = "commercial"`, `license = "LicenseRef-..."`), distributed outside this repo, and
installed with `RAPSCALYON_PACKS_PATH`. The installer applies every security rule to them too.

## 5. Standing constraints **[user, memory]**

Never touch production Supabase projects (PostGlider, TatPlat, JobsGlider) without
explicit approval. Cloud spend only with approval. Do not print secrets. Ask before
outward-facing actions. The public repo carries no production identifiers.
