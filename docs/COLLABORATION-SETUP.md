# Collaboration setup: sharing a Claude Code project

When several people work on a RapScalYon project with Claude Code, the code travels through git but most of what Claude "knows" does not. This page says which parts travel, which stay on one machine, and how to move the valuable part, the context, into files everyone gets.

## What travels with the repository

Commit these and every collaborator's Claude starts with them.

| File or folder | What it carries |
|---|---|
| `CLAUDE.md` (here a symlink to `AGENTS.md`) | Working rules, vocabulary, definition of done. Loaded automatically. It can import other files with `@path`. |
| `.claude/settings.json` | Shared permissions and hooks (for example the verify-on-stop `typecheck`). |
| `.claude/skills/`, `.claude/agents/`, `.claude/commands/` | Shared workflows such as `pack-builder`. |
| `.mcp.json` | Project-scoped MCP servers. Each person supplies their own credentials. |
| `docs/` | Architecture, account modes, vocabulary, pack docs. The durable context. |

## What stays on one machine

| Where | What | Why it does not travel |
|---|---|---|
| `~/.claude/projects/<path>/memory/` | Auto-memory | Per machine, outside the repo. |
| `~/.claude/projects/<path>/*.jsonl` | Session transcripts | Per machine; they also hold tokens, ids and client details. |
| `CLAUDE.local.md`, `.claude/settings.local.json` | Personal instructions and permissions | Untracked on purpose. |

## Move the context into files

The context is usually worth more than the code: why a thing was built this way, what was rejected, what state a feature is in. Memory and transcripts lose it when the person leaves or the machine changes, so write it down where git carries it.

1. **Promote durable memory into `docs/`.** Decisions, runbooks, status and "how to run it" belong in the document that owns the topic. Memory may point at the document; it does not replace it.
2. **End each session with a handover.** Ask Claude to write what was decided, why, what is open and what blocks it into the owning document (and the task tracker), not into the chat.
3. **Do not share raw transcripts.** They are noisy and carry secrets. `/export` saves one conversation to a file when a specific discussion must be handed over; read it before sending.
4. **Index the repo.** A code-graph index (for example `codebase-memory-mcp` with `mode: full`) lets a new collaborator's Claude answer structural questions without reading every file. Indexes are local; each person builds their own.

## Packaging reusable behaviour

Skills, hooks and agents that should reach many projects go in a Claude Code plugin, distributed through a plugin marketplace. Collaborators install it once and receive updates with `/plugin`. A repository-level `.claude/` folder is simpler when the behaviour belongs to one project.

## Private material next to a public repository

This repository is public and self-contained, so private decisions, customer details and ids cannot live in it. Keep them in a separate private repository that collaborators clone next to this one, then give each person an untracked `CLAUDE.local.md` containing one line that imports the private file:

```
@~/projects/<private-repo>/AGENTS.md
```

Keep `CLAUDE.local.md` out of git by adding it to `.git/info/exclude`. A symlink in a shared parent folder would load these rules into unrelated projects, which is why the import is per checkout.

## Before you commit

- Read every path under `.claude/` and any `.mcp.json`; none may hold a token, key or project reference.
- Stage your own files by name. Do not use `git add -A`.
- A new document is linked from `README.md` or the nearest index, and `CHANGELOG.md` is updated in the same commit.

## Onboarding checklist for a new collaborator

1. Clone the repository and open it in Claude Code. `CLAUDE.md` and the skills load by themselves.
2. Create `CLAUDE.local.md` if the project has a private repository (see above).
3. Run the app once, following the project's own quick start (for this repository, [README.md](../README.md)), before changing anything. Seeing it work is the fastest way to understand what a change affects.
4. Read `docs/ARCHITECTURE.md`, then the docs of the pack you will touch.
