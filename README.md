# RapScalYon

A security-first Supabase foundation ("core") plus installable **packs** and a Next.js app base code, for standing up a real, multi-tenant, billing-ready app fast. Packs are Lego bricks: each one is optional, prefixed, tested, removable, and cannot change core.

## What is in the box
See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the layers (core, packs, app base code, tools, integrations), the repositories and the naming rules. Account modes (app accounts or WordPress accounts) are in [docs/AUTH-MODES.md](docs/AUTH-MODES.md). The documentation site (user guide, reference, help center) is at [rapscalyon.documentationai.com](https://rapscalyon.documentationai.com).

- **core** (`supabase/migrations/`): profiles, credits and plan limits (idempotent `charge_credits`), billing-event ledger, rate limiting, subjects (workspaces) and members, MFA gate, `ensure_rls` event trigger, default-deny privileges, and a private `media` storage bucket scoped by workspace. Secrets live in a service-only table, never in `profiles`.
- **packs** (`packs/`, see [docs/CATALOG.md](docs/CATALOG.md)), more than two dozen, in three groups:
  - **Business foundations:** `subject-individual`, `subject-business`, `team`, `people`, `consents`, `calendar`, `item-tracker`, `item-search`, `places`, `real-estate-listings`, `invoice-refunds`, `social-posts`.
  - **Connections:** `wp-fluentauth` (WordPress sign-in), `loops-email`, `turnstile` (bot protection), `posthog-analytics`.
  - **AI apps:** `interior-designs`, `ai-chat`, `chat-with-file`, `chat-with-youtube`, `image-generations`, `image-transforms`, `headshots`, `music-generations`, `voice-transcriptions`, `text-to-speech`, `qr-code-generations`, `content-writer`, `youtube-content`, whose table shapes follow the apps on [builderkit.ai/apps](https://builderkit.ai/apps) (not affiliated).
  
  Pro packs (paid, licensed under [PACK-EXCEPTION.md](PACK-EXCEPTION.md)) live outside this repository.
- **app** (`app/`): Next.js app base code with Supabase auth, a workspace switcher, a nav built from installed packs, pack pages and API routes, public `/packs` marketing pages.
- **tools**: `tools/rapscalyon.py` (installer, validator, test runner, catalog), `deploy.sh`, `Dockerfile`, `app.json`.

## Quick start
```
supabase start && supabase db reset                 # local core
python3 tools/rapscalyon.py pack add packs/item-tracker --app app
python3 tools/rapscalyon.py test
supabase status -o env     # copy API_URL, ANON_KEY and SERVICE_ROLE_KEY into app/.env.local (names in app/.env.example); without it the app returns HTTP 500
cd app && npm install && npm run dev
```
If `supabase start` reports an unhealthy container, start only what the app and tests need: `supabase start -x studio,imgproxy,edge-runtime,logflare,vector,supavisor,mailpit,postgres-meta,storage-api,realtime`.
Hosted: `./deploy.sh --name myapp --org <org-id> --packs "subject-business team item-tracker"`, or `--project <ref>` for an existing project.
Add `--project <ref>` to any `rapscalyon.py` command to target a hosted Supabase project (needs a logged-in `supabase` CLI).

```
rapscalyon.py pack add <dir|name> [--app app]    # validate, apply in one transaction, roll back on any violation
rapscalyon.py pack remove <name> [--app app]
rapscalyon.py pack list | validate <dir> | core | catalog
rapscalyon.py test [--pack name]                 # role-switched SQL suites (anon / owner / other user / service)
```
The interview agent proposes a stack and installs nothing; a person confirms it, the confirmation becomes a ticket, and an executor ([ClawMagic.ai](https://clawmagic.ai)) runs the ticket.

Browser end-to-end test: `app/e2e/README.md`.

## Install validator
A pack is rejected, and its transaction rolled back, if it: leaves RLS off, grants anything to anon, grants table-level UPDATE/INSERT to authenticated, uses `USING (true)`, has rows with no ownership chain, lacks the MFA restrictive policy, has foreign keys without a covering index, ships SECURITY DEFINER functions without `search_path = ''` or without checking the caller, exposes functions not listed in `[db].api_functions`, creates views without `security_invoker`, uses unprefixed names, or changes any core object. Details in [CONTRIBUTING.md](CONTRIBUTING.md); each pack's `docs/SECURITY.md` says what it grants and why.

## Production notes
- Enable leaked-password protection in Supabase Auth (Pro plan setting).
- The RLS helper functions (`has_subject_access`, `is_admin`, `is_subject_owner`, `session_satisfies_mfa`, `get_my_limits`) are intentionally executable by signed-in users, because policies call them as that user; they reveal only the caller's own access.
- `rate_limits` and `user_credentials` have RLS and no policies on purpose: service role only.
- Never expose `SUPABASE_SERVICE_ROLE_KEY` to the browser; the app base code only reads it in server code.

## Licence
AGPL-3.0-or-later for core and official packs (see [CONTRIBUTING.md](CONTRIBUTING.md) for tiers and the contributor agreement). [PACK-EXCEPTION.md](PACK-EXCEPTION.md) additionally lets a pack that uses only the documented pack interfaces carry its own licence, including a proprietary one.
