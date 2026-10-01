# Authoring a RapScalYon pack (guide for the Pack Builder)

A pack is a directory: `pack.toml`, `migrations/NNN_*.sql`, `rollback/NNN_*.sql`, `tests/*.sql`, `docs/README.md`, `docs/SECURITY.md`, and `docs/MARKETING.md` (required for the catalog). Optional: `ui/` pages, `rules/` (GenAI-Logic form). A pack adds tables on top of core; it never alters core objects.

## pack.toml
`[pack]` name (kebab-case), prefix (2-6 lowercase letters, unique), version, description, license, tier (official | verified | community | commercial), requires_core, requires (other packs), conflicts. `[db]` lists tables, functions, `api_functions` (functions users may call), `reference_tables`. Optional `[limits]` (plan caps by name) and `[nav]` entries. Official and verified packs must be AGPL-3.0-or-later. Commercial packs (`license = "LicenseRef-..."`) live in the private plus repo, not this one.

## What the installer rejects (one transaction, rolled back on any violation)
- Any object name not starting with `<prefix>_`; any change to a core object.
- A table with RLS off; any privilege for `anon`; table-level INSERT or UPDATE for `authenticated` (grant columns only); TRUNCATE, REFERENCES or TRIGGER grants.
- A `using (true)` or `with check (true)` policy on a non-reference table; grants with no policy.
- Rows with no ownership chain (needs a foreign key to subjects, profiles or another pack table).
- A missing MFA restrictive policy (call `public.apply_mfa_gate('public.<table>')` for every table).
- A foreign key without an index that starts with the key columns.
- Views without `security_invoker`; materialized views exposed to API roles.
- Functions: must set `search_path = ''`, must not be executable by PUBLIC or anon, user-callable ones must be listed in `api_functions`, and SECURITY DEFINER ones callable by users must check the caller (`auth.uid()`, `has_subject_access`, `is_subject_owner`, `is_admin`).
- Unprefixed function names; secrets in SQL; `create extension` outside schema `extensions`.

## Core helpers a pack uses
`public.subjects` (workspaces), `public.has_subject_access(subject_id)` (members and owner), `public.is_subject_owner(subject_id)`, `public.is_admin()`, `public.set_updated_at()` trigger function, `public.get_plan_limit(tier, name, default)` for plan caps, `public.apply_mfa_gate(table)`, `auth.uid()` (null for service-role and migration code).

## Proven patterns
- **Scoping:** every table carries `subject_id`. Make children consistent with parents using a composite key: parent `unique (id, subject_id)`, child `foreign key (parent_id, subject_id) references parent (id, subject_id)`. A child can then never point into another workspace.
- **Policies:** select/insert/update by `has_subject_access`, delete by `is_subject_owner`. Wrap helper calls as `(select public.has_subject_access(subject_id))`.
- **Column grants:** grant insert and update on named columns only. Anything the client must not set (derived totals, statuses set by the system, currency copied from a parent) is simply left out of the grant.
- **Derived values:** compute in triggers. A SECURITY DEFINER recompute function writes the derived columns; clients cannot. Prefer recompute-from-scratch for correctness; a `generated always as (...) stored` column is fine for same-row arithmetic.
- **State machines:** a before-update trigger lists allowed transitions and raises on others. Check `auth.uid() is not null` before role checks, because service-role code has no user.
- **Owner-only decisions:** inside the trigger, `if (select auth.uid()) is not null and not public.is_subject_owner(subject_id) then raise ...`.
- **Event outbox:** system events are rows written by an after trigger; clients get select only. A worker reads them.
- **Append-only:** grant select and insert only; no update or delete grants.
- **Cascade gotcha:** when a parent row is deleted, cascaded child deletes run after the parent is gone, so a child trigger that looks up the parent finds nothing. Allow that case explicitly.
- **Restrict deletes** on rows that must keep history (refunds, events) with `on delete restrict`.

## Tests
SQL suites in `tests/*.sql`, wrapped in `begin; do $$ ... end $$; rollback;`. Helpers in schema `t`: `t.make_user(email)`, `t.as_user(id)`, `t.as_anon()`, `t.as_admin()`, `t.as_service()`, `t.assert(bool, msg)`, `t.denied(sql)` (true if the statement fails), `t.rows(sql)` (row count). A good suite: the happy path, then one attack per rule (client sets a derived column, wrong status move, over-limit amount, foreign workspace, anon, forged system row), then isolation between two users.

## Definition of done
`python3 tools/rapscalyon.py pack validate packs/<name>` passes; `pack add` installs; `test --pack <name>` passes; `pack remove <name>` leaves no residue; full `test` still passes; `catalog` regenerated; README, SECURITY and MARKETING written; CHANGELOG line added.

## Business rules and GenAI-Logic
RapScalYon's direction is declarative rules (GenAI-Logic: Sum, Count, Formula, Constraint, Copy, Event). Today a pack enforces rules in SQL and may also ship `rules/declare_logic.py` in GenAI-Logic form. That file is written from the GenAI-Logic documentation and is not run until GenAI-Logic is integrated; say so in the pack README. Rule mapping: derived parent total from children is Sum; arithmetic on one row or a parent value is Formula; a condition that must hold is Constraint; take a parent value once at creation is Copy; a side effect on commit is Event.

## Reference pack
`invoice-refunds` (prefix `ir`) shows every pattern above: derived columns, a state machine, an owner-only decision, an outbox event, and a test suite that attacks each rule. Its migration and tests are attached as reference documents.
