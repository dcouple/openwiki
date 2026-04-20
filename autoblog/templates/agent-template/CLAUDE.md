# autoblog agent

You are the autoblog agent, running inside a container on this host.

## Working context

- Working directory: `/agent`
- Skills: `.claude/skills/` — see list below
- Memory: `.claude/memory/MEMORY.md` (index) and individual files beside it

## Filesystem roots

Three roots, each with its own git history:

- `/agent` — your config: CLAUDE.md, skills, memory. Edit freely; no rebuild needed.
- `/site` — the Astro site. Three sub-paths:
  - `/site/repo.git` — bare git object store (do not work inside this directory)
  - `/site/prod` — worktree on branch `main`; Caddy serves `/site/prod/dist/`
  - `/site/dev` — worktree on branch `dev`; Astro dev server runs from here
- `/vault` — the agent's working clone of the vault bare repo at `/vault-remote.git`.
  Layout is organized by content type, not subject:
  - `raw/` — user-writable only. The agent reads raw but never modifies it. If you find yourself about to write anything under `raw/`, stop — something is wrong.
  - `wiki/daily/`, `wiki/notes/`, `wiki/ideas/`, `wiki/entities/`, `wiki/sources/` — agent-authored pages, organized by content type.
  - `log.md` — chronological record of vault operations (ingests, edits, roundups). Append-only.
  - `index.md` — catalog of wiki pages by content type. Updated on every ingest.
  - `CLAUDE.md` — full wiki schema (filing heuristic, required frontmatter, conventions). Read this before the first ingest of a session.
  User writes `raw/`; the agent writes everything else. Every agent-authored wiki page must carry frontmatter with `type:`, `ai-generated: true`, and a `sources:` list pointing back to the raw file(s) that informed it.

### Vault git discipline

Every vault-touching skill does `git -C /vault pull --rebase` before reading and `git -C /vault push` after committing. The agent is a git client, just like the user's laptop or phone — treat sync as first-class, not optional.

Never touch `/vault-remote.git` directly; it is the bare remote. All reads and writes go through the working clone at `/vault`.

## Site publishing model

Visibility is controlled by a single frontmatter field:

```yaml
status: draft      # visible only on dev (:4321)
status: published  # visible on both dev and prod (:8080)
```

Every `getCollection` call filters explicitly:

```ts
getCollection('timeline', ({ data }) =>
  import.meta.env.PROD ? data.status === 'published' : true
)
```

This is applied in every page that queries a collection. Missing one leaks drafts to prod.

Content locations:
- Timeline entries: `/site/dev/src/content/timeline/<slug>.md`
- Standalone pages: `/site/dev/src/content/pages/<slug>.md`  → served at `/<slug>`
- Home page body: `/site/dev/src/home.md` (NOT under `src/content/` — direct-imported by index.astro)

## Deploy model

All edits happen on the `dev` branch in `/site/dev`. To publish:

1. The `deploy` skill commits pending dev changes, runs `npm run build` in `/site/dev` (build failure aborts), merges `dev` → `main` in the shared bare repo, then rsyncs `/site/dev/dist/` → `/site/prod/dist/`. Caddy serves the new build immediately.
2. Rollback uses `git revert` (non-destructive new commit) then rebuilds prod's dist.

You own all git operations in `/site`. Users say "deploy" or "roll back"; you translate to git + rsync.

Git discipline:
- Never `git reset --hard` for rollback (use `git revert`).
- Never resolve `main` by name from inside `/site/dev` — use `git -C /site/prod rev-parse main`.
- The build in `/site/dev` is the gate; do not skip it.

## Available skills

Run these in response to the triggers listed:

| Skill | Trigger phrases |
|---|---|
| `deploy` | "deploy", "ship", "publish the site", "push to prod" |
| `rollback` | "roll back", "undo last deploy", "revert" |
| `publish-draft` | "publish <slug>", "mark <post> as published" |
| `update-home` | "update the home page", "change the intro" |
| `new-page` | "create a new page for X", "add a page about Y" |
| `discard-dev` | "throw away dev changes", "reset dev", "start over on dev" |
| `ingest-source` | "ingest", "process raw", "process new files", "catch up on raw" |
| `write-timeline-entry` | "write a timeline entry", "write a post about X" |
| `weekly-roundup` | "weekly roundup", "what did I work on this week" |

## Access

You are reached via `ssh -p 2222 autoblog@host`. `ANTHROPIC_API_KEY` is delivered to your shell via `~/.ssh/environment` (not `.bashrc` — this works for both interactive and non-interactive SSH).

## Memory

Read `.claude/memory/MEMORY.md` at the start of each session to orient yourself. Add significant decisions, conventions, and preferences there as you work.
