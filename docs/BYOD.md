# Bring your own database (BYOD) (DRAFT 2026-10-05)

Status: decided by the owner on 2026-10-05. Provenance marks: **[repo]** read in a file named here, **[verify]** not yet confirmed.

An app a client already runs (a BuilderKit app, a Lovable export, a hand-built Supabase project) has a database full of real data. RapScalYon's guarantees (default-deny row-level security, the MFA gate, subjects and workspaces, credits, a security-checked installer with rollback) hold only in a database that core created. So there are exactly two ways to use an existing database, and one thing we never do.

## Mode 1: Attach (read-only by default)

A RapScalYon product, report or automation connects to the existing database without installing anything in it.

- **Dedicated role.** The client (or we, with their approval) creates one Postgres role for RapScalYon. It gets SELECT on the named tables, or on views in a separate schema (`rsy_ext`), and nothing else. Writes go only through named functions the client reviews. No service-role key, no superuser.
- **Manifest.** A small file per attached database lists the project reference, the tables and columns we may read, the column that identifies the owning user (for example `user_id`), and any write function. Nothing outside the manifest is queried.
- **Secrets.** The connection string lives only in the server or executor environment, never in a prompt, a repo or a chat (SPEC principle 6).
- **Claims.** We install no core and no packs, and we make no RapScalYon security claim about that data. Row-level security in the client's database is the client's.
- **Production data stays put.** Never copy it into a demo.
- **Use it for:** dashboards, reports, the Make shopping blueprint, any read-mostly integration.

## Mode 2: Migrate (convert into the foundation)

A new Supabase project gets core, then the data is imported through a reviewed migration. This is the "separate, reviewed piece of work" named in `pickaxe/kb/vertical/supabase-foundation.md` [repo].

- App users become core profiles; each user gets an individual subject (`subject-individual` pack).
- App credit and plan columns map onto core credits and the billing ledger; payment webhooks are replaced by core's billing webhook fed from FluentCart (`docs/BILLING.md`).
- Each app table becomes a pack table: prefixed, with `subject_id`, row-level security through core's helper functions, a removable migration and tests.
- Files move to storage that does not force a paid plan (Cloudflare R2 is the recommendation from the interioraidesigner project) or to core's private media bucket.
- The migration is reviewed by a person and run by the installer in one transaction.

## Never: install core into the existing database in place

The installer rejects anything that weakens row-level security, and a foreign `public` schema with unprotected tables, its own `users` table and its own policies cannot satisfy that. It would also break "one project per product" and make rollback meaningless. If a client wants the guarantees, they take Mode 2.

## Choosing

| Situation | Mode |
|---|---|
| Read the data, add reports or an integration | Attach |
| Keep the old app running while we watch it | Attach |
| Move the product onto RapScalYon (billing, credits, packs, MFA) | Migrate |
| Unsure | Attach first; Migrate is a later, separate approval |

## Pack conversion of a third-party app

Converting an app's modules into packs is a Migrate-mode project. The first one is the BuilderKit interior design app (BKIDA); its plan is `.dwp/plans/PLAN_bkida_pack_conversion/` (local, gitignored). Rules for any such conversion:

- Write pack code against the schema; never copy the app's source into a pack. BuilderKit's README says MIT, but it links to a custom commercial licence that forbids redistributing the boilerplate (2026-10-05). Check a third-party app's licence before reusing any of its code, and treat the schema and behaviour as the only inputs.
- Commercial work that depends on a paid boilerplate lives in a separate private repo (`tier = "commercial"`), not here.
- A schema read from a live client database is saved under the plan, not in this repo (it can reveal the client's data model).
