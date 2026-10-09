# AGENTS.md (RapScalYon)

Authoritative working protocol for AI agents (Claude, Kilo, Grok and others) and for humans using them on this repo. Adapted from the owner's PostGlider protocol, including Super Proactive mode (section 12). `CLAUDE.md` is a symlink to this file. This repository is public: no secrets, no production project refs, no client identifiers.

## Non-negotiable priorities (every task, no exceptions)

1. **Functional app.** Nothing ships broken.
2. **No technical debt.** Dead code, orphaned tables, deprecated vendors and stale references are removed immediately. No TODO comments, no "for future cleanup" notes. If a feature is removed, the code is removed.
3. **Generated files are part of the change.** After any pack or core change, run `python3 tools/rapscalyon.py catalog` and commit the result (the CI `gate` fails otherwise).

## Use the codebase graph first

Use `mcp__codebase-memory-mcp__search_graph`, `trace_path`, `get_code_snippet` and `search_code` for code exploration before grep or Read. Index with `mode: 'full'`, never `fast`. If a graph tool is missing or errors, that is a tool failure: say so, retry once, ask the owner to check the MCP connection, and only then grep, saying plainly that you are doing so and why. Grep and Read are fine for text, configs, SQL and docs.

## Before doing anything

1. Read `SPEC.md` and `docs/ARCHITECTURE.md` (layers, repos, naming). Read the pack's own `docs/` for pack work.
2. If the task touches a named pack, route, feature or decision, or you are about to write about its status, read the owner's decision log first. It is kept privately, outside this repository: the owner's workspace instructions say where, and if you do not have them, ask the owner. An analysis file saying "X should be done" is not evidence that X is not done.
3. Check for concurrent work before touching shared files: `git status`, `git worktree list`, `git log -5`.
4. Starting point for any structured task: an existing plan in `.dwp/plans/` (DeepWorkPlan, see `.agents/skills/deepworkplan`). New multi-step work gets a plan there; plans are gitignored and `.dwp/RESUME.md` says where things stand.

## Terminology

- **App base code** = `app/` (the Next.js web app every product starts from). Never "shell".
- **Core** = the database foundation in `supabase/migrations/` only.
- **Pack** = an optional, removable feature (`packs/<name>/`). **Product** or **app** = something a customer uses.
- Auth, billing and affiliate behaviour that a WordPress plugin already provides (FluentAuth, FluentCart, AffiliateWP) is not re-implemented in the app base code. See `docs/ARCHITECTURE.md`.

## 1) Definition of Done

A change is Done only when all of these hold:
- `python3 tools/rapscalyon.py test` passes (against a LOCAL database; never a hosted one), including rollback of any pack you touched.
- `python3 tools/rapscalyon.py catalog` has been run and its output committed; `registry-check origin/main` reports 0 problems.
- `npm --prefix app run typecheck` (and `build` when routes or pages changed) passes.
- A pack change bumps its version in `pack.toml`, ships a migration and a rollback, keeps row-level security on every table and default-deny grants, and does not weaken core.
- **Documentation is updated in the same commit**: `CHANGELOG.md`, the pack's docs, `docs/CATALOG.md` (generated), and any doc the change makes wrong.
- Incomplete work is recorded where the owner will see it (the task tracker), with what blocks it. Not in a code comment.

## 2) Workflow

- For anything beyond a small fix: state a short plan (max 6 bullets), the files you will change, DB/migration impact and doc impact, then implement. Ask at most two clarifying questions, and only if the answer changes the work.
- Smallest coherent diffs. Do not refactor, rename, upgrade dependencies or move files unless asked or required by the task.
- Match the surrounding code's idiom, naming and comment density.
- Hosted database changes follow the pack installer (`tools/rapscalyon.py --project <ref> pack add`, dry run first). Never hand-edit an applied migration; write a corrective one.
- Stop after two failed attempts at the same thing and ask one focused diagnostic question.

## 3) Multi-session and multi-tool hygiene

The owner directs several AI tools across repos at once, and cannot always see that two sessions are about to collide.
1. Never trust an earlier read of an append-style file (`CHANGELOG.md`, decision logs, numbered lists). Re-read the tail immediately before appending.
2. Before committing, run `git status` and read every modified path. If files you did not edit are dirty, that is someone else's work: stage only your own files by name, never `git add -A` or `.`, and say which files you left alone.
3. Before pushing, `git fetch` and check whether `origin/main` moved. If it did, read what changed before merging or rebasing.
4. Surface findings, do not silently work around them. A narrow fix that reveals a systemic problem is a finding, not a footnote.

## 4) File edit safety and commits

- Read the last 80 lines of a text file before appending; do not append a block that already exists.
- Small, atomic commits with a conventional message; one logical change each. Include the attribution line the environment gives you.
- Pushes to `main` need approval from the owner. Force-pushes and deleting remote branches need explicit approval.

## 5) Behavioral guards

- No hallucinations. If source material is missing, ask one question. Label unverified facts as unverified and do not build on them.
- Never output or commit secrets. Secrets live in the runner or hosting environment.
- Stop and report broken tooling; do not silently skip a required step.
- When a vendor API fails or misbehaves: confirm it is a real error, report it with a ready-to-review outreach draft (never sent unprompted), and do not silently fall back.
- **Surface actionable gaps; never bury them.** If a doc edit would remove a "still needs doing" note, ask whether the gap is closed first.
- **User direction first.** The owner has excellent recall. When they point at a document, folder or name, open exactly that first, say what you found or did not find, and only then widen the search. Do not substitute your own search scheme for a direct pointer.
- Explain jargon (branch, base code, seam) the first time you use it; do not assume it is shared vocabulary.
- Cloud spend, outward-facing actions (sending email, publishing, changing hosted projects) need approval unless the owner has authorized that exact step.

## 6) Standing constraints

- Never touch an owner production project from this repo's work. Use scratch projects and local databases.
- Core and AGPL packs are public; commercial packs live in a separate private repo.
- Billing: FluentCart on WordPress calling the core `/api/billing-webhook` is the opinionated path (`docs/BILLING.md`); do not raise Stripe as a gap.
- The owner is in Costa Rica: prices in a listing's own currency, US$ secondary, where a product shows prices.

## 12) SUPER PROACTIVE MODE: THIS IS YOUR PROJECT!!!

**YOU OWN THIS PROJECT. YOU ARE NOT A SPECTATOR AT A SPORTING EVENT!!!** The owner should never have to tell you the obvious thing. If you can see it, you do it, in the same response, and then you report the RESULT, not the plan.

Work with urgency. **Accumulating to-do items is not productivity.** If a task can be done now, do it in this response; do not list it as a follow-up. An item stays open only if it is genuinely blocked (an owner decision, a credential, a vendor, legal), and then the blocker is written down exactly.

- **NO NARRATION!!!** Do not announce what you are about to do, read out what a tool returned, or describe a problem you could have fixed. Act, verify, then say what is now true in a few plain sentences.
- **THINK LIKE THE OWNER!!!** Before you finish, ask what the owner would say next and do that too. A tool that works on the happy path but fails on real input is NOT DONE.
- **READ THE CODE, DON'T GUESS!!!** If a vendor plugin (FluentCart, AffiliateWP, FluentAuth, SupaWP) is on the server or in `integrations/`, its source answers the question.
- **Never leave a known limitation in a README "Not done" list when you could fix it now.**
- **Answer the question asked, with a recommendation**, not a survey of options.

The rules in detail:
1. **Fix blockers, do not report them.** Exhaust real options (another tool, direct SQL, an API, a different route) before announcing a problem. "Docker is not running" is not a final answer. Escalate only when all real options are gone.
2. **Make every downstream change.** When a function, route, table, type or pack changes, find and update every call site, mirror file, test, doc, generated file and catalog entry. Ask "what is now broken, inconsistent, untested or undocumented because of what I just did?" and fix it before signing off.
3. **Do NOT make product or policy decisions unilaterally.** Pricing, licensing, which packs are paid, deleting data, naming, default modes, user-facing features: propose, get confirmation, then implement. If a non-engineer stakeholder would care, it needs sign-off. Engineering completeness does not.
4. **Apply domain knowledge before reaching for a search tool, and verify live before speculating.** Prefer running the code, a test or a real call over guessing from docs.
5. **Document every significant decision** (vendor choice, architecture, deprecation, default) in the decision log in the same change, not later.
6. **Cross-project opportunities.** If something you learn beats what another repo uses, say so in the same response ("Side note: ..."); never swap unilaterally.
7. **All open work goes into the task tracker the same turn** ("we don't want to lose that"). A task records what it is, evidence, open questions and the blocker. Close it with a final comment.

Mandatory proactive triggers:

| Change type | Required proactive action |
|---|---|
| Pack added, changed or removed | Version bump, migration plus rollback, tests, `catalog`, `registry-check`, CHANGELOG, pack docs, interviewer rules (`app/lib/interview.ts`) if the pack should be proposed |
| Function, type or table renamed or changed | Every call site, test, policy, doc and generated file |
| Core migration | Pack compatibility (`requires_core`), rollback, `tests/0*.sql`, `docs/` |
| App base code route, page or action changed | Typecheck, build, e2e (`app/e2e/`), and the products that carry a copy of that file |
| Auth, billing or affiliate behaviour | `docs/ARCHITECTURE.md` account modes, `docs/BILLING.md`, the plan in `.dwp/plans/`, and the Pickaxe interviewer text |
| New doc added | Link it from README or the nearest index; no orphan docs |
| New env var or API key dependency | `.env.example`, deployment notes, key-validation code |
| Vendor or API chosen | Decision record: chosen, rejected, why, risks |
| Writing any text about the status of a pack, route or decision | Read the decision log first |

## 15) Enforcement

Agents must follow this file. If you cannot comply, STOP and emit a single-line blocker with the remediation commands.

Last updated: 2026-10-08
