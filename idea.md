autoblog
========

A personal, agent-maintained knowledge base with a public website. Inspired by Andrej Karpathy's LLM Wiki pattern (reproduced at `docs/idea.md`), extended with a separate public site whose pages are composed on demand by a conversational agent.

For the architecture deep-dive, see `docs/autoblog-overview.md`. For the phased build plan, see `tmp/ready-plans/`.

The core idea
-------------

Most personal knowledge bases fall apart because the maintenance burden outgrows the value. Links rot, summaries go stale, cross-references get forgotten. LLMs don't get bored with bookkeeping, so let them do it.

autoblog is three layers:

1.  A **private Obsidian vault**. You drop raw material (articles, PDFs, images, clippings) into a `raw/` folder; an agent reads it and incrementally maintains a wiki of entity pages, concept pages, summaries, and cross-references. This is the Karpathy pattern.

2.  A **public website**, separate from the vault, generated deliberately from vault content. Nothing in the vault is automatically public. The agent writes site pages on explicit request, tracks their provenance, and publishes them only when told to.

3.  A **conversational agent**. It lives on the server, has skills and memory, and owns the bookkeeping for both the vault and the site. You direct it; it does the work.

Why separate vault from site
----------------------------

Two reasons. First, safety — no surface area for accidental leaks. The vault can hold the most sensitive raw source material because nothing there is ever rendered publicly. Second, clarity — a site page is an act of intentional authorship, not a side effect of note-taking. "What gets published" and "what the agent knows" are cleanly separate questions, each with its own rules.

Where it runs
-------------

The whole system runs inside a single Docker container, plus a Caddy container that serves the public site. Two phases, same image:

-   **Phase 1**: on your laptop. You validate the full system end-to-end before touching a VPS.
-   **Phase 2**: on a VPS. Same container, same compose file, same agent. Only `.env` differs (public ports, real domain, Let's Encrypt TLS via Caddy).

This means there is no "dev vs. prod" container divide. Whatever you prove works on the laptop is what runs on the VPS.

Inside the container, three roots:

```
/vault     private knowledge base — git repo
  raw/       sources + attachments (you write here, agent never does)
  wiki/      agent-authored pages
  log.md     chronological record of what the agent has done
  index.md   catalog of wiki pages
  CLAUDE.md  wiki schema

/site      Astro project — git repo with two worktrees
  prod/      on main branch; built and served by Caddy
  dev/       on dev branch; served by Astro dev server (shows drafts)

/agent     Claude Code working directory
  CLAUDE.md  top-level instructions
  .claude/
    skills/   how to do specific things (ingest, publish, deploy, …)
    memory/   what the agent has learned across sessions
```

Three roots. One agent. The agent has read access to all three and write access to `vault/wiki/` (never `vault/raw/`), `site/dev/` (and the prod worktree for merge + deploy), and its own `.claude/`.

Multi-device access
-------------------

You talk to the agent from any device with an SSH client. The container exposes sshd on port 2222; phone, laptop, desktop, any of them can connect. Each session lands in the same tmux session on the server, so you can pick up a conversation where you left off regardless of which device you're on.

The vault is a git repo, and every device is a git clone. The canonical copy is a bare git repo inside the container (`/vault-remote.git`), reachable over the same SSH port. You use Obsidian on each device, with the Obsidian Git plugin handling pull/push automatically.

This matters for the common case: you're on your phone during the day, you drop a raw note into the `raw/` folder in Obsidian, and by evening the agent processes it. Your write patterns and the agent's write patterns are cleanly disjoint — you only touch `raw/`, the agent only touches everything else — so you rarely hit conflicts.

Setup details per device (key management, plugin configuration, iOS quirks) live in `docs/vault-sync.md`.

The wiki
--------

Agent-owned. It creates and updates pages as new raw material arrives, maintains `index.md`, appends to `log.md`, and keeps cross-references consistent. Conventions live in `vault/CLAUDE.md` and evolve over time.

You read the wiki in Obsidian, on whichever device is handy. You rarely write it yourself; when you do, the agent picks up the change on its next run because the whole vault is a git repo.

The website
-----------

An Astro project. The site is a separate artifact — not a rendering of the vault, but a deliberate publication composed from it. Initial structure:

```
site/src/
  home.md                 landing page body
  content/
    timeline/             chronological entries
      2026-04-18-something.md
    pages/                standalone pages
      about.md
      rust-migration.md
```

Routes:

-   `/` — home. `home.md` at the top, then the latest N timeline entries inline.
-   `/timeline` — full reverse-chronological timeline.
-   `/timeline/<slug>` — individual timeline entry.
-   `/<slug>` — standalone pages (e.g. `/about`, `/rust-migration`).

Intentionally minimal. Richer structure gets added later by asking the agent to create new routes and layouts — the entire Astro project is agent-editable, including layouts, styles, and config.

Draft vs. published
-------------------

One frontmatter field decides visibility:

```yaml
---
title: "..."
status: draft       # or "published"
---
```

The dev server shows everything. The production build filters drafts out. Publishing a page is flipping the flag and letting the deploy pipeline pick it up.

The agent
---------

Claude Code, running inside the container. You interact with it conversationally; you don't memorize commands.

-   **Skills** (`agent/.claude/skills/`) tell the agent how to do specific tasks: ingest a source, write a timeline entry, publish a draft, deploy the site, roll back a deploy, do a weekly roundup. Each skill is a markdown file. The agent can add, edit, and refine skills as you work together.

-   **Memory** (`agent/.claude/memory/`) holds what the agent has learned across sessions: your preferences, the themes you care about, conventions you've asked it to follow. Every new session reads memory on startup.

You don't run rigid commands. You say *"update the home page to emphasize the rust stuff"* and the agent — armed with its skills and memory — does it. If there's a task you do often that doesn't yet have a skill, you teach the agent one and it's saved for next time.

Deployment and version control
------------------------------

The site repo has two git worktrees sharing one bare repo:

-   `site/prod/` on `main` — what the public sees.
-   `site/dev/` on `dev` — what the agent edits, what you preview.

Flow:

1.  You talk to the agent. It edits files in `dev/`, committing as it goes.
2.  You preview at `http://localhost:4321` (Astro dev server; Phase 1 direct, Phase 2 via `ssh -L` tunnel).
3.  When you're happy, you say *"deploy"*. The agent runs `astro build` in `dev/` as the sanity gate, merges `dev` into `main`, copies `dev/dist/` to `prod/dist/`, and Caddy serves the new version.
4.  If the dev build fails, the deploy is aborted. Production cannot break from a bad agent edit.
5.  *"Roll back"* uses `git revert` on main — a new commit that undoes the last one, non-destructively — and rebuilds.

You never type a git command. The agent owns git the same way it owns the site.

The vault follows the same philosophy in a different shape: it's a bare repo that all your devices — and the agent — clone from. The agent auto-commits and pushes at the end of each ingest; your devices pull on a timer.

Interacting with the agent
--------------------------

One wrapper on your laptop, `autoblog`, that SSH-tails into the container and attaches to a named tmux session:

```bash
autoblog                      # Phase 1: local Docker
AUTOBLOG_HOST=my.domain autoblog --tunnel   # Phase 2: VPS; --tunnel forwards the dev server
```

From inside tmux you run `claude` for a new conversation, `claude -c` to continue the most recent, or `claude -r` to pick from a list.

Two layers of session:

-   **tmux** (inside the container) is process persistence — survives SSH drops and device sleep.
-   **Claude sessions** are chat histories — each conversation is a file; resume any of them.

Skills and memory persist across all sessions. Teach the agent something in one conversation; it knows it in the next — from any device.

Technology choices
------------------

-   **Runtime**: Docker + Docker Compose. One image, two phases. A VM with Docker installed is all the host needs.
-   **Site**: Astro. Content collections, MDX, easy static output, room to grow.
-   **Agent**: Claude Code with its native skills and memory systems.
-   **Web server**: Caddy (public) — auto-TLS via Let's Encrypt in Phase 2.
-   **Access**: SSH + key auth. No Tailscale. The container's sshd is the one port that's public in Phase 2.
-   **Multi-device sync**: Obsidian Git. Every device — including iOS and Android phones — is a git clone of the vault.
-   **Deploy gate**: `astro build` success in `dev/` is required before any `dev → main` merge.
-   **Time**: all schedules and "weekly" windowing are Pacific Time.

What's not here (yet)
---------------------

-   No automatic ingest. Sources arrive in `raw/`; the agent processes them when you tell it to.
-   No cron. Weekly roundups happen when you ask for them, via a skill, not a schedule.
-   No auto-publishing from vault to site. Every public page is an intentional act.
-   No public chat UI. You talk to the agent over SSH.
-   No RAG / vector store. `index.md` + grep + a reading agent is enough at the target scale.
-   No public/private tagging in the vault. The vault is private; the site is public.
-   No rich editorial workflow. `status: draft` vs `status: published` is the only lifecycle.

All of these can be added later if and when they earn their keep.

Principles
----------

1.  **The agent is the interface.** Don't build rigid CLIs. Teach skills; refine them as you learn.
2.  **Intentional publishing.** No page reaches the public by accident. Every visible page is an explicit act.
3.  **The build is the gate.** Production cannot regress from an agent edit; broken builds don't ship.
4.  **Version control is invisible.** Git is the substrate, not the interface. You think in "deploys" and "rollbacks," not commits and merges.
5.  **Separate concerns, shared agent.** Vault, site, and agent each have their own root, their own rules, and their own history. The agent is the only thing that spans them.
6.  **One image, two phases.** Whatever runs on the laptop is what runs on the VPS. Phase 2 is an `.env` change, not an architecture change.
7.  **Small now, room later.** The initial structure is boring. Additions earn their way in.

Credits
-------

The wiki pattern is from Andrej Karpathy's "LLM Wiki" note, reproduced at `docs/idea.md`. The Memex framing — a personal, curated knowledge store with trails between documents — traces back to Vannevar Bush, 1945. autoblog is one instantiation of these ideas, optimized for a single user's personal site, a private vault, and a conversational agent as the UI.
