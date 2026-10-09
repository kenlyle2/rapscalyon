# Architecture: the parts of RapScalYon and what to call them

Standard term (owner decision, 2026-10-08): the Next.js web app that ships in this repo is called the **app base code**. Older documents and commit messages call it the "app shell" or "shell"; they mean the same thing.

## The layers

| Layer | Where | What it is | Who sees it |
|---|---|---|---|
| **Core** | `supabase/migrations/` | The database foundation: profiles, credits and `charge_credits`, billing-event ledger, rate limiting, subjects (workspaces) and members, the MFA gate, `ensure_rls`, default-deny privileges, private `media` storage. Packs cannot change it. | Nobody directly; it is the security model |
| **Packs** | `packs/<name>/` | Optional features, each with prefixed tables, row-level security, a rollback, tests and (some) UI and API routes. Examples: `item-search`, `turnstile`, `loops-email`. | Customers, through the pages a pack adds |
| **App base code** | `app/` | The Next.js web app every product starts from: login, sign-in link, forgot and reset password, the auth callback, the workspace switcher, a navigation menu built from the installed packs, pack pages and API routes, public `/packs` pages. | Everyone who uses the product in a browser |
| **Tools** | `tools/`, `deploy.sh`, `Dockerfile` | `tools/rapscalyon.py` (installer, validator, test runner, catalog), deployment helpers. | The person installing |
| **Integrations** | `integrations/` | WordPress-side plugins and settings: FluentAuth hardening, the FluentCart bridge, AffiliateWP-FluentCart, offers, SupaWP notes. | The site owner, on WordPress |
| **Interview layer** | `pickaxe/` (public KB), role prompts kept privately | The AI agents that interview a person and propose a stack, and their knowledge base. | The person describing their business |

"Core" in these docs means the database layer only. The app base code is a separate layer; core and the app base code share the repo version (see `CHANGELOG.md`), and each pack versions itself in `pack.toml`.

## The repositories

| Repo | Visibility | Holds |
|---|---|---|
| `kenlyle2/rapscalyon` | public | Core, official packs, the app base code (`app/`), tools, integrations, public Interview knowledge base |
| Private repositories | private | Commercial packs, the Interview role prompts and playbooks, the marketing and client sites, and the owner's internal operating records. Not described in this repository |
| A product repo (one per product) | private | One product: a copy of the framework (core, the app base code, tools) plus its own packs |

## How a product gets the app base code

A product repo carries its own copy of `app/`. Packs are copied into it by `app/scripts/sync-packs.mjs` (UI into `app/app/(app)`, server routes into `app/app/api/<name>`). The base itself (login, callback, layout, middleware) is copied once at creation and then edited in place, so copies drift: CarShopper's login lacked account recovery because the base code never had it. There is no automatic update path today. **[verified: git history of the login page; no sync tool for the base exists in the repo]**

Rule until one exists: a fix to anything in the app base code goes into `rapscalyon/app` first, then is copied to the products, and the product's changelog says so.

## Account modes

Where login, recovery, MFA and billing live is a choice made per product (decided 2026-10-08, plans `PLAN_auth_modes_wordpress` and `PLAN_auth_recovery_core`):

- **Mode B (default for any real business):** WordPress with FluentAuth, FluentCart and AffiliateWP, bridged to the app by SupaWP.
- **Mode A (semi-deprecated):** the app base code's own Supabase sign-in, recovery and MFA.

## Naming rules

- Use **app base code** for `app/` in this repo and its copies. Do not write "shell".
- Use **core** only for the database foundation.
- Use **pack** for an optional, removable feature; **product** or **app** for a finished thing a customer uses (CarShopper).
- The npm package in `app/package.json` is still named `rapscalyon-app`; it is the app base code.
