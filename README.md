# RapScalYon

A security-first Supabase foundation ("core") plus installable feature **packs**, for skeleton-ing an app fast.

- **core** (`supabase/migrations/20260101000000_core_foundation.sql`): profiles, credits/limits ledger (idempotent `charge_credits`), billing events, rate limiting, subjects (workspaces), MFA gate, `ensure_rls` event trigger, default-deny privileges. Secrets live in a service-only table, never in `profiles`.
- **subject packs** (pick one): `subject-individual`, `subject-business`.
- **feature packs**: `team` (invites and roles), `real-estate-listings`, `jobs-tracker`, `social-posts`.

```
python3 tools/rapscalyon.py pack add <name>      # validate, apply in one transaction, roll back on any violation
python3 tools/rapscalyon.py pack remove <name>
python3 tools/rapscalyon.py pack list
python3 tools/rapscalyon.py test [--pack name]   # role-switched SQL suites (anon / owner / other user / service)
```

Local dev: `supabase start`, apply core (`supabase db reset`), then `pack add`. Requires `psql` and Python 3.11+.

## Install validator
A pack is rejected, and its transaction rolled back, if it: leaves RLS off, grants anything to anon, grants table-level UPDATE/INSERT to authenticated, uses `USING (true)`, has rows with no ownership chain, lacks the MFA restrictive policy, has unindexed foreign keys, ships SECURITY DEFINER functions without `search_path = ''` or without checking the caller, exposes functions not listed in `[db].api_functions`, creates views without `security_invoker`, uses unprefixed names, contains secrets, creates extensions outside `extensions`, or changes any core object.

See each pack's `docs/SECURITY.md` for what it grants and why. Pack format: `pack.toml`, `migrations/`, `rollback/`, `server/`, `ui/`, `tests/`, `docs/`.

License: AGPL-3.0-or-later.
