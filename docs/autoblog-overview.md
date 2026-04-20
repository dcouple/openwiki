# autoblog — Architecture Overview

This document is the durable architecture reference. It explains *what* autoblog is, the pieces it's made of, how they fit together, and how the system reaches the web and your devices. For *how to build it*, see the phased plan files under `tmp/ready-plans/`. For the original design motivation, see `idea.md`; for the LLM Wiki pattern it builds on, see `docs/idea.md` (Andrej Karpathy's note).

## What autoblog is

A personal, agent-maintained knowledge base with a public website, running out of a single Docker container.

Three layers, one agent:

1. **Vault** — a private Obsidian vault (markdown + attachments) maintained as a git repo. You drop sources into `raw/`; the agent reads them and maintains a wiki in `wiki/`.
2. **Site** — an Astro project published deliberately from vault content. The vault is never auto-mirrored to the site; the agent composes pages on your instruction.
3. **Agent** — Claude Code, running inside the container, with skills for ingest, publish, deploy, rollback, etc. You talk to it over SSH + tmux.

The vault, site, and agent each have their own filesystem root and their own git history. The agent is the only thing that spans them.

## Runtime topology

Two services in one `compose.yml`, running on one host (your laptop in Phase 1; a VPS in Phase 2):

```
Host
│
├─ autoblog container (Debian, sshd + tmux + node + claude CLI)
│    ports:
│      ${SSH_BIND:-127.0.0.1}:2222 → container:22   (SSH + git-over-SSH)
│      ${DEV_BIND:-127.0.0.1}:4321 → container:4321 (Astro dev server)
│    volumes:
│      autoblog_vault  → /vault          (working clone)
│      autoblog_vault_remote → /vault-remote.git  (bare, push/pull target for all devices)
│      autoblog_site   → /site           (bare repo + prod + dev worktrees)
│      autoblog_agent  → /agent          (CLAUDE.md, skills, memory)
│      autoblog_claude → /home/autoblog/.claude  (session state)
│      autoblog_ssh    → /etc/ssh        (persisted host keys)
│    processes: bootstrap → astro dev (bg) → sshd -D (fg)
│
└─ caddy container
     ports:
       ${CADDY_BIND:-127.0.0.1}:${CADDY_HTTP_PORT:-8080}  → container:80
       ${CADDY_BIND:-127.0.0.1}:${CADDY_HTTPS_PORT:-8443} → container:443
     mounts autoblog_site read-only; serves /site/prod/dist/
```

Caddy does not reverse-proxy the dev server. Dev is accessed directly (Phase 1) or via SSH `-L` tunnel (Phase 2). Caddy's only job is serving the public production site.

## Single image, env-driven phase switch

Phase 1 (laptop) and Phase 2 (VPS) use the **same image** and the **same `compose.yml`**. Only `.env` differs:

| Var | Phase 1 default | Phase 2 (VPS) |
|---|---|---|
| `SSH_BIND` | `127.0.0.1` | `0.0.0.0` (public SSH required) |
| `DEV_BIND` | `127.0.0.1` | `127.0.0.1` (**never** public; use SSH `-L`) |
| `CADDY_BIND` | `127.0.0.1` | `0.0.0.0` |
| `CADDY_HTTP_PORT` | `8080` | `80` |
| `CADDY_HTTPS_PORT` | `8443` | `443` |
| `DOMAIN` | `localhost` | your real domain |

Port mappings are written as `"${SSH_BIND:-127.0.0.1}:2222:22"` so the fail-safe default is loopback: forgetting to set the env var on a VPS breaks SSH (obvious), rather than silently exposing the dev server (silent compromise).

## Multi-device sync: Obsidian Git + bare vault remote

All user-facing devices (phone, laptop, desktop) participate in the vault via git, not file sync. The VPS holds the canonical bare remote. Every device is a git clone.

```
                  ┌──────────────────────────────────────┐
                  │ autoblog container on host (VPS)     │
                  │                                      │
                  │   /vault-remote.git   ← bare, origin │
                  │        │                             │
                  │        │ push/pull (ssh on :2222)    │
                  │        ▼                             │
                  │   /vault              ← agent works  │
                  │    ├─ raw/            ← user writes  │
                  │    ├─ wiki/           ← agent writes │
                  │    ├─ log.md                         │
                  │    └─ index.md                       │
                  └──────────────────────────────────────┘
                           ▲          ▲          ▲
                           │          │          │
                   git push/pull over SSH (port 2222)
                           │          │          │
                    ┌──────┘          │          └──────┐
              ┌─────────┐      ┌──────────┐      ┌─────────┐
              │ Laptop  │      │ Desktop  │      │  Phone  │
              │ Obsidian│      │ Obsidian │      │ Obsidian│
              │ + Git   │      │ + Git    │      │ + Git   │
              └─────────┘      └──────────┘      └─────────┘
```

Why this model:

- **Write patterns rarely conflict.** You only write `raw/`; the agent only writes outside `raw/`. Real conflicts require you to edit the same raw file on two devices before either syncs — rare.
- **Agent uses standard git.** Every vault-writing skill starts with `git pull --rebase` and ends with `git push`. No custom sync logic.
- **Phone is a first-class citizen.** Mutagen has no mobile client; Obsidian Git does.
- **One system to debug.** Failures surface as visible git errors, not silent file drift.

Setup per device:
- **Desktop/laptop Obsidian:** clone `autoblog@host:/vault-remote.git`, open in Obsidian, enable Obsidian Git plugin (auto-commit + pull/push on interval).
- **Phone Obsidian:** same flow using Obsidian Mobile + the mobile-compatible Obsidian Git plugin. SSH key stored on device.

Detail on plugin config and mobile SSH lives in `docs/vault-sync.md` (added in Phase 1c).

## Vault layout — wiki organized by content type

Inside `/vault`, the agent maintains `wiki/` with five content-type subdirs (no subject-matter folders — subject lives in `[[wikilinks]]` and tags):

```
/vault
├── raw/                    user writes here; attachments under raw/assets/
├── wiki/
│   ├── daily/              dated entries (daily updates, life updates, TILs) — one file per day, append sections
│   ├── notes/              concept pages / learning material — one file per concept
│   ├── ideas/              longer-lived, evolving ideas to develop over time
│   ├── entities/           people, orgs, tools, projects
│   └── sources/            per-raw-source summaries (traceability record)
├── log.md                  chronological agent audit trail; also "what's been ingested"
├── index.md                catalog of wiki pages by content type
└── CLAUDE.md               full schema — filing heuristic, required frontmatter, conventions
```

Agent's filing rule per ingest: one content-type judgment (daily / note / idea / source-only), **always** a matching `wiki/sources/` page for traceability, entity pages updated where relevant.

Every agent-authored page has frontmatter with `type:`, `ai-generated: true`, and a `sources: [raw/...]` list. `ai-generated` distinguishes agent output from anything you write in the wiki by hand; `sources` is the audit path for any claim that looks surprising later.

Subject-matter navigation (MOCs at `wiki/_maps/`) is deferred — add once the wiki has ~50 pages and actually needs curated entry points. Premature to build into an empty vault.

Pattern anchored in Andrej Karpathy's LLM Wiki note (see `docs/idea.md`); the content-type subdirs are this project's adaptation to keep agent filing decisions deterministic.

## Stateful container — what's in the image, what's in volumes

Design principle: **the container runs for months. Adding skills, installing npm deps, and updating content must NOT require a rebuild.**

**In the image** (changing requires `docker compose build`):
- System packages: node, git, openssh-server, tmux, claude CLI
- `/opt/autoblog/bin/entrypoint.sh`, `bootstrap-volumes.sh`
- `/etc/ssh/sshd_config`
- `/opt/autoblog/templates/` — agent/site/vault seed templates (used only on first boot)

**In named volumes** (change freely at runtime, persist across restarts):
- `/agent/` — CLAUDE.md, skills, memory. Edit directly; no rebuild.
- `/site/` — Astro project + `node_modules` + built `dist/`. `npm install` works live.
- `/vault/`, `/vault-remote.git/` — content and its git history.
- `/home/autoblog/.claude/` — Claude Code session history.
- `/etc/ssh/` — sshd host keys (persistence critical for SSH fingerprint stability).

When in doubt: code and tools live in the image; everything the agent reads, writes, or learns lives in a volume.

## How you interact with it

From any device with SSH:

```
$ autoblog                 # wrapper: ssh -t autoblog@host "tmux new-session -A -s main -c /agent"
[inside tmux]
$ claude                   # start or resume a conversation with the agent
> deploy                   # invokes the deploy skill
```

Two session layers:
- **tmux** (on the host) keeps processes alive across SSH drops.
- **Claude sessions** are chat histories; resume any via `claude -c` or `claude -r`.

Skills and memory persist across all sessions. Teach once; remembered forever (or until you edit the file).

## Publishing model

One frontmatter field decides visibility:

```yaml
---
title: "..."
status: draft       # or "published"
---
```

- **Dev server** (`:4321`, always-on inside the container): shows everything.
- **Prod** (Caddy on `:8080` / `:80`): shows only `status: published`.

Deploy flow (the `deploy` skill):

1. Agent commits pending changes on the `dev` branch in `/site/dev`.
2. Agent runs `npm run build` in `/site/dev` — this is the sanity gate. Build failure aborts the deploy.
3. Agent merges `dev` → `main` in the shared bare repo.
4. Agent copies `/site/dev/dist/` → `/site/prod/dist/`. Caddy serves the new build immediately.

Rollback uses `git revert` (non-destructive — creates a new commit that undoes the last), then re-copies the prior `dist/`.

## Design principles

Inherited from `idea.md`; repeated here because they shape every decision downstream.

1. **The agent is the interface.** Don't build rigid CLIs. Skills evolve as you work.
2. **Intentional publishing.** No page reaches the public by accident.
3. **The build is the gate.** Production cannot regress from an agent edit.
4. **Version control is invisible.** You think in deploys and rollbacks, not commits and merges. The agent owns git.
5. **Separate concerns, shared agent.** Vault, site, agent — three roots, three histories, one spanning actor.
6. **Small now, room later.** The initial structure is boring. Additions earn their way in.
7. **Loopback-by-default bindings.** Any port binding without an explicit IP is a bug.
8. **Stateful long-lived container.** Day-to-day changes happen in volumes, not image rebuilds.

## Anti-patterns to avoid

- Using Tailscale as a private-access layer. SSH + `-L` meets the same security goal with no extra service. (The file `docs/tailscale.md` is a leftover research note from a prior iteration and will be removed.)
- Auto-filtering drafts via collection config. Astro 5 doesn't support it; filter at every `getCollection` call site.
- Reverse-proxying the dev server through Caddy. Caddy's only job is the public prod site.
- Writing port mappings without `${BIND_VAR:-127.0.0.1}:…`. Silent public exposure waits for the day someone forgets.
- Baking `node_modules` or templates into the image in a way that requires rebuilding to update. Templates are read on first boot only; `node_modules` lives in a volume.
- Using Mutagen for vault sync. Lacks mobile support; conflicts silently resolved; replaced by Obsidian Git.

## Phase roadmap

Four plan files, each independently demoable:

| Phase | File | What you get |
|---|---|---|
| **1a** | `tmp/ready-plans/phase-1a-container-scaffold.md` | `docker compose up` brings up a container you can SSH into; `claude` runs; Caddy serves a placeholder page. No Astro, no vault. |
| **1b** | `tmp/ready-plans/phase-1b-site-deploy.md` | Adds the Astro site, two-worktree git model, deploy/rollback/publish skills. `localhost:4321` shows dev, `localhost:8080` shows prod. |
| **1c** | `tmp/ready-plans/phase-1c-vault-ingest.md` | Adds the vault (bare remote + working clone), ingest/roundup skills, Obsidian Git setup for laptop/desktop/phone. Full Phase 1 system. |
| **2**  | `tmp/ready-plans/phase-2-vps.md`              | Moves the validated Phase 1 system to a VPS: DNS, firewall, Let's Encrypt, .env overrides. No architectural changes — just environment. |

Each phase plan has its own success criteria, files-changed list, validation loop, and anti-patterns section.
