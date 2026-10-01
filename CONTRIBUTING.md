# Contributing a pack

A pack is a directory: `pack.toml`, `migrations/NNN_*.sql`, `rollback/NNN_*.sql`, `tests/*.sql`,
`docs/README.md`, `docs/SECURITY.md`. Look at `packs/jobs-tracker` for a small example.

## Workflow
1. Copy an existing pack, rename, pick a unique 2–3 letter `prefix`.
2. `python3 tools/rapscalyon.py pack validate packs/<name>` (static checks).
3. `python3 tools/rapscalyon.py pack add packs/<name>` against a local DB, then `... test`.
4. `pack remove <name>` must leave no residue (tables, functions, pricing rows, registry rows).

## What the installer enforces
Installation runs in one transaction; any violation rolls everything back.
- Every object name starts with `<prefix>_`; packs never alter core objects (core fingerprint is checked).
- RLS on every table; `anon` has no privileges; `authenticated` gets column-level INSERT/UPDATE grants only
  (no table-level INSERT/UPDATE, no TRUNCATE/REFERENCES/TRIGGER).
- No `using (true)` / `with check (true)` policies on non-reference tables; no dead grants.
- Rows must be owned: a foreign key to `profiles`/`subjects` (or another pack table).
- Call `public.apply_mfa_gate` so the restrictive MFA policy is applied.
- Foreign keys need an index starting with the FK column.
- Views are `security_invoker`; materialized views are not exposed to API roles.
- Functions: `search_path = ''`, not executable by PUBLIC/anon, user-callable ones listed in
  `[db].api_functions`, and SECURITY DEFINER functions must check the caller.
- Packs key on core `subjects`; use `requires` only for a real dependency on another pack.

## Tests
Each pack ships SQL suites under `tests/` using the helpers in `tests/_helpers.sql`: show that a user sees
only their rows, cannot touch another subject's rows, and that column grants block privileged columns.

## Licence
GPL-3.0-or-later. Do not include secrets, customer data or proprietary logic.
