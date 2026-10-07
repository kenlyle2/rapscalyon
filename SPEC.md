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
7. **Independence and capability.** No single platform may trap a client or us. Every dependency (Supabase, Pickaxe, ClawMagic, FluentCart, Sanity) has its coupling point named and a way out; we keep the capability to run the same work elsewhere, and we say so in the docs.

## 0b. The stack at a glance **[repo and docs named in each row]**

| Layer | What | Status | Where it is documented |
|---|---|---|---|
| Data, auth | Supabase: core migrations, subjects, RLS, MFA gate | built | README.md, `supabase/migrations/` |
| Functionality | Packs (AGPL here; commercial "plus" packs in a separate repo) | built, 11 packs | `docs/CATALOG.md`, CONTRIBUTING.md |
| App shell | Next.js with a nav built from installed packs | built | `app/` |
| Front door | Pickaxe agents: Stack Interviewer (proposes the stack), Pack Builder (writes a pack) | live, retests pending | private `rapscalyon-app` repo |
| Executor | ClawMagic.ai runs the execution ticket | decided; unverified end to end | private `rapscalyon-app` repo |
| Business rules | GenAI-Logic declarative rules | proven on SQLite only | `packs/invoice-refunds` |
| Billing | FluentCart on WordPress; webhook in core | built; real webhook sample unverified | `docs/BILLING.md` |
| Affiliates | AffiliateWP (owner decision 2026-10-04) with a FluentCart adapter plugin | adapter built (`integrations/affiliatewp-fluentcart/`) | `docs/BILLING.md` |
| Email, bot protection, analytics | Loops, Turnstile, PostHog packs | built | `docs/CATALOG.md` |
| Client websites | Sanity content, one multi-tenant React Router site, hosted Studio per client | built 2026-10-03; Studio hand-off to a client is a human step | private `rapscalyon-app` repo |
| Provisioning | `tools/client_site.py`: unclaimed Sanity project, claim link, draft seeding | built, tested on a real claim | private `rapscalyon-app` repo |

Customer journey (**[proposal]**, assembled from the pieces above): subscribe through FluentCart, interview in Pickaxe, receive a stack proposal and execution ticket, ClawMagic installs the packs into the client's own Supabase project, the provisioning tool creates their Sanity project and drafts their site from the interview, the client claims it, reviews drafts in their Studio, and their domain is added to `SANITY_SITES`.

Worked example of a child pack from a brief, with prompts: `car-deal-finder-build-plan.md` (outside the repo, see 0c).

## 0c. Related documents

In this repo: `README.md`, `CONTRIBUTING.md`, `CHANGELOG.md`, `docs/BILLING.md`, `docs/CATALOG.md`, `docs/COMMERCE-STACKS.md`, `docs/BYOD.md`, `docs/operations.mdx`.

The role prompts, working policy, decision log and client-facing playbooks live in the private `rapscalyon-app` repo. Schema extracts of the owner's private products stay out of every repo; only genericized material is moved here.

Other repos: `rapscalyon-plus` (commercial packs), `rapscalyon-app` (private: role prompts, strategy and client docs), `rapscalyon-main` (marketing site and the multi-tenant client site template).

## 0d. Hosting **[checked 2026-10-03]**

Client sites run as one multi-tenant Node app on shared Node hosting (the plan allows a handful of Node apps, so one app serves many domains). Whether the host answers for every client domain without a separate app slot per domain is the biggest unverified risk to multi-tenancy; test it before selling it. Fallbacks: a serverless edge platform or a small VPS.

## 1. Purpose **[user]**

RapScalYon aims to be the fastest way to build any business app. It is a Next.js shell
plus a Supabase backend, shaped by lessons learned on earlier production apps.
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
pack policy. A subject is a business profile, a job-search persona, and so on. **[proposal]** If "objects" is the intended public name, rename
in core in the same change as every downstream reference; never leave a wrong name in place.

## 3. Item model **[repo: packs/item-tracker, packs/item-search]**

The base packs are generic: a **subject** owns **items** (`item-tracker`) and saved searches with a
review queue (`item-search`). A specific kind of item is a **child pack** that keys 1:1 on the base
table and adds typed columns (class-table inheritance, kind enforced by a trigger). "Item" is used
instead of "object" to avoid Supabase's `storage.objects`. `subjects` keeps its name (owner decision).
Child packs, including the commercial job packs, are distributed separately.

## 3b. Destination **[user]**

ClawMagic.ai is the opinionated destination for clients, users and builders: Pickaxe designs, ClawMagic executes
and operates.

## 3c. Features (possibility) **[user, proposal]**

Packs are database and app building blocks. Clients should see something simpler: **features** they switch on, such as email, billing, or offer sync. A feature may bundle a pack (database), an executor job in ClawMagic or OpenClaw (a watcher or publisher), and a connector to a commodity tool such as FluentCart. "Pack" stays the technical term for the installable database unit; "feature" is the word for clients and the interviewer. Nothing is renamed in the installer, the registry or the live Pickaxe agents yet. First candidate: `offer-sync` (`integrations/fluentcart-offers/`): plugins and a runner around FluentCart, no database pack.

ClawMagic as the day-to-day business-management interface for clients is a possibility the owner believes in; it rests on unverified claims and on one real run. ClawMagic is described by the owner as a superset of OpenClaw (not verified by us), and each client may run an OpenClaw instance; that is why principle 7 matters.

## 4. Licensing model **[user, proposal]**

Open core: the core, the base packs and the installer are AGPL-3.0-or-later. "Plus" packs are
commercial (`tier = "commercial"`, `license = "LicenseRef-..."`), distributed outside this repo, and
installed with `RAPSCALYON_PACKS_PATH`. The installer applies every security rule to them too.

## 5. Standing constraints **[user, memory]**

Never touch the owner's production Supabase projects without
explicit approval. Cloud spend only with approval. Do not print secrets. Ask before
outward-facing actions. The public repo carries no production identifiers.
