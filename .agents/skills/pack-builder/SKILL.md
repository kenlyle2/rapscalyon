---
name: pack-builder
description: Build, change or remove a RapScalYon pack (packs/<name>/) so it passes the installer's validator, its tests, rollback, catalog and registry checks the first time. Use whenever the task adds a pack, changes a pack's tables, functions, routes or pages, bumps a pack version, or adds an [auth] declaration. Not for app base code or core changes (see AGENTS.md).
---

# Build a RapScalYon pack

A pack is an optional, removable feature in `packs/<name>/`. The validator in `tools/rapscalyon.py` (`load_pack`, `app_install`, the post-apply checks) is the authority; if this file and the validator disagree, the validator wins and this file gets fixed in the same change.

## 0. Before writing anything
- Read `SPEC.md`, `docs/ARCHITECTURE.md` and the decision log named in AGENTS.md if the pack touches a named feature.
- Look at the closest existing pack (`turnstile` is the smallest; `loops-email` shows policies, grants and cron). Copy its shape, not its words.
- Check what the pack needs from other packs (`requires`) and which packs may hook the same tables (e.g. a welcome-email trigger on `profiles`). Your tests must not assume they are alone in the database.
- Product or policy choices (pricing, tier, licence, default modes, names visible to customers) are the owner's: propose, get a yes.

## 1. Layout
```
packs/<name>/
  pack.toml
  migrations/001_*.sql      # forward only; never edit an applied one, write 002
  rollback/001_*.sql        # one per migration, exact inverse
  tests/001.sql             # role-switched suite using tests/_helpers.sql (schema t)
  docs/README.md  docs/SECURITY.md  docs/MARKETING.md   # README + SECURITY are required
  server/    -> app/app/api/<name>/   (route.ts handlers)
  ui/        -> app/app/(app)/        (pages; gets nav entries from [nav])
  public/    -> app/app/(public)/     (unauthenticated pages; declare them in [auth].public_paths)
```
`server/`, `ui/`, `public/` are optional. Ownership of installed files is recorded in `app/lib/packs/owners.json`; `pack remove` deletes only what the pack owns.

## 2. pack.toml rules (enforced)
- `[pack]` requires name (kebab-case, 2-41 chars), prefix (2-6 lowercase letters; pick one no other pack uses - check `packs/*/pack.toml`), version, description, license, tier, requires_core, requires, conflicts.
- tier is `official | verified | community | commercial`. official/verified must be AGPL. commercial uses `LicenseRef-<name>` and lives in the private `rapscalyon-plus` repo.
- `[db]` lists every table and function (these feed the catalog and the removal check).
- `[auth]` (optional): `login_path` (local path or https URL) or `login_env` (env var name, uppercase) - never both; `signup` bool; `public_paths` local paths. Two packs declaring a login make the installer stop.
- `[nav]`, `[cron]`, `[limits]` as in existing packs. A cron `path` should be a route the pack ships under `server/`.

## 3. SQL rules (enforced after applying, in a transaction that rolls back on any violation)
- Every object name starts with `<prefix>_`.
- Every table: row level security on, an owner (a foreign key to `profiles`, `subjects` or another pack table), a restrictive MFA policy via `select public.apply_mfa_gate('public.<table>')`, and at least one permissive policy if API roles have grants.
- No grants to `anon`. For `authenticated`: select at table level; insert/update only with column lists (never table-level insert/update; never truncate/references/trigger).
- No policy with `using (true)` / `with check (true)` on a non-reference table.
- Views `security_invoker`; materialized views not exposed to API roles.
- `create extension` must target schema `extensions`.
- Every function sets `search_path = ''` and schema-qualifies everything; none may be executable by PUBLIC or anon (revoke explicitly). Dynamic `execute` is allowed only inside `security definer` functions.
- Core must be unchanged: no altered columns, policies, functions, constraints or grants on core tables. Core's `ensure_rls` trigger switches RLS on automatically - do not rely on it, write the `enable row level security` line.
- A trigger on a shared table (`profiles`, `auth.users`) must never block the write: wrap its body in `exception when others then return new`.

## 4. Tests (`tests/001.sql`)
- Use `t.make_user`, `t.as_user`, `t.as_service`, `t.as_anon`, `t.assert`, `t.rows`, `t.denied`. Wrap in `begin; ... rollback;`.
- Cover: owner reads/writes own rows, another user sees nothing, anon denied, direct writes denied where only functions may write, each function's happy path and refusal.
- **Isolate**: count only rows your pack created (filter by your own event/key or by the ids you made). Other packs' triggers also insert on sign-up; an unfiltered `count(*)` breaks when they are installed.
- Never leave rows behind; the suite must pass on a database that already holds other packs' data.

## 5. Docs (same commit)
- `docs/README.md`: what it does, install, how it is used, remove. `docs/SECURITY.md`: threats, what is stored, what is not. `docs/MARKETING.md`: plain-language description for customers (copy the turnstile format).
- `CHANGELOG.md` entry (re-read its tail first; other sessions append). Any doc the change makes wrong.
- Never write a "Not done" list for something you could do now; open work goes in the task tracker with its blocker.

## 6. Commands, in this order
```
python3 tools/rapscalyon.py pack validate packs/<name>
python3 tools/rapscalyon.py pack add packs/<name> --app app      # local database only
python3 tools/rapscalyon.py test --pack <name>
python3 tools/rapscalyon.py pack remove <name> --app app         # prove no residue; then add again if the app run needs it
python3 tools/rapscalyon.py test                                  # full suite
python3 tools/rapscalyon.py catalog                               # commit docs/CATALOG.md, registry/packs.json, app/lib/packs/*.generated.ts, pickaxe/kb/platform/<name>.md
python3 tools/rapscalyon.py registry-check origin/main            # 0 problems
npm --prefix app run typecheck                                    # and build when routes/pages changed
```
The installer refuses a local database holding tables that core and the installed packs do not declare (another project's schema, or a pack applied with raw psql). Fix the database, do not bypass it. Installing writes replay files under `supabase/migrations/` (gitignored); `pack remove` deletes them, so never edit or delete them by hand.

Changing an existing pack: bump `version` in pack.toml (registry-check fails otherwise), ship `00N` migration plus rollback, never edit an applied migration.

## 7. Downstream (the "what did I just break" list)
- App routes/pages: typecheck, build, `app/e2e/`, and products that carry a copy of the file.
- New env var: `.env.example`, deployment notes, key validation.
- Auth/billing/affiliate behaviour: `docs/ARCHITECTURE.md`, `docs/AUTH-MODES.md`.
- Hosted databases: only through the installer with `--project <ref>`, dry run first, never a production project from this repo.

## 8. Commit
`git status`; stage only your files by name; conventional message; `git fetch` and look at `origin/main` before pushing; pushes to main need the owner's approval.
