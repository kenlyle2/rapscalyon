# RapScalYon SPEC

Status: working draft, updated 2026-10-03 (v0.5.0). Provenance is marked throughout:
**[user]** stated by the owner, **[repo]** verified in a file named in the text,
**[proposal]** a recommendation that needs the owner's decision. Nothing else is asserted.

## 0. Vision **[user, this session's statements; proposal where marked]**

A non-developer describes a business to an interviewer agent and ends up with a working, secure, billing-ready app and a modern public website, owning their data and able to leave. The pieces are bought where they are a commodity and built only where they differentiate (COTS-first, vendors switchable). Honest limits are part of the product: nothing is claimed that has not been tested, and unverified items are marked as such.

Principles:
1. **Secure by construction.** The installer rejects any pack that weakens row-level security, MFA or grants; the core is default-deny.
2. **Lego packs.** Optional, prefixed, tested, removable, unable to change core.
3. **COTS-first, reversible.** Billing is FluentCart, email is Loops, bot protection is Turnstile, content is Sanity, design runs in Pickaxe, execution in ClawMagic. Each can be swapped; the coupling points are named in the docs.
4. **No bullshit.** No plugin stores, no server toolchains the site does not need, no scanner noise; delete redundancies, no technical debt.
5. **Client owns their data.** Each client owns their Sanity account and their Supabase project; our hosting is a convenience they can leave, and leaving is a sold upgrade.
6. **Agents move work, humans approve.** Interview answers become drafts, never published text; credentials never go into an agent prompt.

## 0b. The stack at a glance **[repo and docs named in each row]**

| Layer | What | Status | Where it is documented |
|---|---|---|---|
| Data, auth | Supabase: core migrations, subjects, RLS, MFA gate | built | README.md, `supabase/migrations/` |
| Functionality | Packs (AGPL here; commercial "plus" packs in a separate repo) | built, 11 packs | `docs/CATALOG.md`, CONTRIBUTING.md |
| App shell | Next.js with a nav built from installed packs | built | `app/` |
| Front door | Pickaxe agents: Stack Interviewer (proposes the stack), Pack Builder (writes a pack) | live, retests pending | `docs/PICKAXE.md` |
| Executor | ClawMagic.ai runs the execution ticket | decided; unverified end to end | `docs/CLAWMAGIC.md` |
| Business rules | GenAI-Logic declarative rules | proven on SQLite only | `docs/VAL-CALL.md`, `packs/invoice-refunds` |
| Billing | FluentCart on WordPress; webhook in core | built; real webhook sample unverified | `docs/BILLING.md` |
| Affiliates | AffiliateWP (owner decision 2026-10-04) with a FluentCart adapter plugin | not built | `docs/DECISIONS.md`, `docs/CLIENT-PLAYBOOK.md` |
| Email, bot protection, analytics | Loops, Turnstile, PostHog packs | built | `docs/CATALOG.md` |
| Client websites | Sanity content, one multi-tenant React Router site, hosted Studio per client | built 2026-10-03; Studio hand-off to a client is a human step | `docs/CLIENT-SITES.md`, `docs/DECISIONS.md` (2026-10-03 entries) |
| Provisioning | `tools/client_site.py`: unclaimed Sanity project, claim link, draft seeding | built, tested on a real claim | `docs/CLIENT-SITES.md` |

Customer journey (**[proposal]**, assembled from the pieces above): subscribe through FluentCart, interview in Pickaxe, receive a stack proposal and execution ticket, ClawMagic installs the packs into the client's own Supabase project, the provisioning tool creates their Sanity project and drafts their site from the interview, the client claims it, reviews drafts in their Studio, and their domain is added to `SANITY_SITES`.

Worked example of a child pack from a brief, with prompts: `car-deal-finder-build-plan.md` (outside the repo, see 0c).

## 0c. Related documents

In this repo: `README.md`, `AGENTS.md` (working policy), `CONTRIBUTING.md`, `CHANGELOG.md`, `docs/DECISIONS.md` (dated decisions and lessons, including the Sanity choice, the claim path, the trial downgrade, hosting options and multi-tenancy), `docs/CLIENT-SITES.md` (recipe, pricing, Sanity announcements and how they fit, verified and unverified points), `docs/BILLING.md`, `docs/PICKAXE.md`, `docs/CLAWMAGIC.md`, `docs/CATALOG.md`, `docs/VAL-CALL.md`, `docs/BACK-OFFICE.md` (what runs the company back office, and why it is not an app).

Outside this repo, in the owner's working folder `~/projects/infra-eval/` (not under version control; named here so they can be found): `rapscalyon-packs-architecture.md` (how the packs were derived from PostGlider, TatPlat and JobsGlider), `rapscalyon-manifest.toml` (which objects are core or pack), the three `*-schema-extract.md` and policy files, and `car-deal-finder-build-plan.md`. They contain schema detail of private products, so they stay private; move only what is genericized.

Other repos: `rapscalyon-plus` (commercial packs), `rapscalyon-main` (marketing site, the multi-tenant client site template and the Studio, https://rapscalyon.surf).

## 0d. Hosting and limits **[checked 2026-10-03]**

Account: Hostinger shared web hosting, 5 Node.js "apps", unlimited websites, 50 GB. Measured over SSH: 7 TB disk partition shared, our home 911 MB (the site build 290 MB), inode use 34% of the partition, 8192 open files per process, a LiteSpeed Node runtime (`lsnode`) running two worker processes of about 115 MB each. CPU and memory caps are CloudLinux per-account limits that are not readable from inside the account.
From Hostinger's public pages (marketing, not a contract; verify in the account): 2 CPU cores and 3 GB RAM per plan, **unlimited bandwidth with no meter**, free CDN, SSL, daily backups. So bandwidth is not the constraint; **CPU and RAM during traffic bursts and the single Node app are**. Sources: https://www.hostinger.com/ph/web-apps-hosting/react-hosting, https://www.hostinger.com/compare/hostinger-vs-vercel.
**Unverified and the biggest risk to multi-tenancy:** whether a Hostinger Node app answers for client domains added as separate websites in the panel, or each domain is its own vhost and app slot. Test before selling it (see `docs/CLIENT-SITES.md`). Fallback: Cloudflare Workers free tier or a small VPS (`docs/DECISIONS.md`).

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
