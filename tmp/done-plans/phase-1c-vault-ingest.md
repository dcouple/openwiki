# autoblog Phase 1c — Vault, Ingest, Obsidian Git Sync

## Overview

Adds the third layer: a private vault that the agent reads and curates, and a multi-device sync model so you can add raw notes from phone/laptop/desktop.

At the end of this phase:

- `/vault-remote.git` is a bare git repo inside the container; `/vault/` is the agent's working clone of it.
- `autoblog@host:/vault-remote.git` is reachable over SSH (port 2222). Laptop, desktop, and phone all clone it via Obsidian Git.
- The user writes only to `/vault/raw/`; the agent writes to everything else (`wiki/`, `log.md`, `index.md`).
- The agent has skills for `ingest-source`, `write-timeline-entry`, `weekly-roundup`.
- Every vault-writing skill starts with `git pull --rebase` and ends with `git push` — the agent is a first-class git client, just like the user's devices.
- `docs/vault-sync.md` covers Obsidian Git setup on each platform.
- Ingest uses `log.md` as the "what's been processed" record (Karpathy's pattern). No separate manifest file.

Full Phase 1 system works on one host after this phase.

## Why this order

1a gave us a runtime. 1b gave us a public site. 1c gives us the private knowledge base — the part the agent spends most of its time on — and the multi-device input path that makes the system usable day-to-day.

Doing it last means the deploy/rollback flow is already battle-tested by hand-authored timeline entries before the much-larger ingest surface starts touching it.

## Prerequisite

Phases 1a and 1b are complete and their validation checklists pass.

## Success criteria

- [ ] `docker compose build` still succeeds with the vault template bundle.
- [ ] First boot seeds `/vault-remote.git` (bare) and clones it into `/vault/` with an initial commit.
- [ ] `/vault/raw/`, `/vault/wiki/`, `/vault/log.md`, `/vault/index.md`, `/vault/CLAUDE.md` all exist.
- [ ] `git clone autoblog@localhost:/vault-remote.git` works from the host, over port 2222.
- [ ] From a second clone, `echo foo > raw/test.md && git add . && git commit -m test && git push` reaches the bare remote.
- [ ] Inside the container, `git -C /vault pull` brings the pushed file into the agent's working copy.
- [ ] SSH in, start `claude`, say "ingest raw/test.md" → agent reads the file, writes or updates wiki pages, appends to `log.md`, commits in `/vault`, pushes to `/vault-remote.git`.
- [ ] Pushing from the second clone after the agent has pushed works cleanly (disjoint paths: user writes `raw/`, agent writes outside it).
- [ ] `docs/vault-sync.md` documents Obsidian Git setup for laptop/desktop/phone with complete step-by-step instructions.
- [ ] Port bindings remain loopback-only.

## Files created or changed in this phase

```
/Users/tbrownio/repos/autoblog/
├── compose.yml                          ← UPDATE: add autoblog_vault + autoblog_vault_remote volumes
│
├── autoblog/
│   └── bootstrap-volumes.sh             ← UPDATE: seed vault template + create bare repo + clone working dir
│
├── agent-template/
│   ├── CLAUDE.md                        ← UPDATE: document /vault root + git pull/push discipline
│   └── .claude/skills/
│       ├── ingest-source.md             ← NEW (simplified per Karpathy: log.md as the record)
│       ├── write-timeline-entry.md      ← NEW
│       └── weekly-roundup.md            ← NEW
│
├── vault-template/                      ← NEW (seeded into /vault on first boot)
│   ├── CLAUDE.md                        # wiki schema (Karpathy + content-type subdirs)
│   ├── log.md
│   ├── index.md
│   ├── .gitignore                       # ignores .obsidian/, .trash/
│   ├── raw/.gitkeep
│   └── wiki/
│       ├── daily/.gitkeep
│       ├── notes/.gitkeep
│       ├── ideas/.gitkeep
│       ├── entities/.gitkeep
│       └── sources/.gitkeep
│
└── docs/
    └── vault-sync.md                    ← NEW (Obsidian Git setup for laptop/desktop/phone)
```

## Reference material

```yaml
- url: https://github.com/denolehov/obsidian-git
  why: Obsidian Git plugin — desktop + mobile. Auto-commit, auto-pull/push on interval.

- url: https://help.obsidian.md/mobile
  why: Obsidian Mobile filesystem model. Vaults live in app storage; SSH keys stored in app-private files.

- url: https://git-scm.com/book/en/v2/Git-on-the-Server-Setting-Up-the-Server
  why: Bare repo pattern for a shared git remote reachable over SSH.

- file: /Users/tbrownio/repos/autoblog/docs/idea.md
  why: Karpathy's LLM Wiki pattern. Ingest = drop source into raw, tell LLM to process. log.md is the chronological record. No separate manifest.

- file: /Users/tbrownio/repos/autoblog/docs/autoblog-overview.md
  why: Multi-device sync diagram and stateful-container design principles.
```

## Known gotchas

```
# CRITICAL: The vault is in TWO places inside the container:
#   /vault-remote.git  — bare, canonical history; what external devices push to
#   /vault             — working clone; where the agent reads and writes
# The agent NEVER touches /vault-remote.git directly. It works in /vault and syncs
# via `git pull --rebase` before reads and `git push` after writes.

# CRITICAL: Bare repo receives pushes fine by default. Non-bare working dir would
# require `receive.denyCurrentBranch = updateInstead` and has gotchas. We use the
# bare-repo model — same pattern as /site/repo.git in Phase 1b. Symmetric.

# CRITICAL: The user writes to raw/; the agent writes to everything else. Real
# conflicts require the user to edit the SAME raw file from two devices before
# either pushes. Rare. When they do happen, git push errors are the signal —
# don't try to auto-resolve; surface them.

# CRITICAL: Ingest uses log.md as the record of what's been processed. We do NOT
# maintain a separate processed.md manifest with SHA tracking. This was an
# invention of an earlier plan iteration; it is not Karpathy's pattern. For
# 5-10 sources/day with a human in the loop, the chronological log is sufficient.
# Scale up to sha tracking the first time you actually hit the pain.

# CRITICAL: Before the agent reads anything from /vault, it must `git pull --rebase`
# to pull in pushes from the user's devices. Before it returns control to the
# user, it must `git push`. Every vault-writing skill embeds these steps.

# CRITICAL: The autoblog user already has shell access over SSH for the agent.
# Git-over-SSH uses the same account: clients run
#   git clone autoblog@host:/vault-remote.git
# No additional user or sshd config is needed. The autoblog user's authorized_keys
# already controls access.

# CRITICAL: Obsidian Mobile + Obsidian Git. The plugin works on iOS and Android,
# but with a slower sync model (timer-based) and requires SSH private keys stored
# in app-private storage. Document setup clearly in docs/vault-sync.md.

# CRITICAL: The vault's .obsidian/ folder (auto-generated workspace metadata) is
# gitignored — devices each maintain their own workspace state. Committing it
# would cause constant spurious churn from each device's window layout changes.
```

## Architecture changes (delta over 1b)

```
autoblog container, new volume layout:
  autoblog_vault         → /vault              (agent's working clone)
  autoblog_vault_remote  → /vault-remote.git   (bare; external devices push/pull here)

Bootstrap additions:
  - Seed /vault-remote.git as bare repo with initial vault template as first commit.
  - Clone /vault-remote.git → /vault (working dir).
  - Configure /vault's remote `origin` pointing at /vault-remote.git.

Git topology (same pattern as /site in 1b):
  /vault-remote.git  (bare, shared object store)
       │
       ├── clone → /vault (inside container, agent-owned)
       ├── clone → laptop (Obsidian vault, Obsidian Git plugin)
       ├── clone → desktop (Obsidian vault, Obsidian Git plugin)
       └── clone → phone (Obsidian Mobile, Obsidian Git plugin)

Access:
  ssh -p 2222 autoblog@host  → shell for the agent
  git clone autoblog@host:/vault-remote.git  → same SSH, git command instead of shell
```

## Implementation tasks

### Task 1 — Update compose.yml

Add to the autoblog service `volumes:`:
```yaml
      - autoblog_vault:/vault
      - autoblog_vault_remote:/vault-remote.git
```

Add to the top-level `volumes:`:
```yaml
  autoblog_vault:
  autoblog_vault_remote:
```

No port or healthcheck changes.

### Task 2 — Update bootstrap-volumes.sh

Add the vault-seeding block after site seeding, before the readiness marker:

```bash
# Seed /vault-remote.git (bare) + /vault (working clone) on first boot
if [ ! -d /vault-remote.git/HEAD ]; then
  echo "[bootstrap] seeding /vault-remote.git + /vault"

  # Build initial vault content in scratch
  rm -rf /tmp/vault-seed
  mkdir -p /tmp/vault-seed
  cp -r "$TEMPLATES/vault-template/." /tmp/vault-seed/
  cd /tmp/vault-seed
  git init -b main
  git add .
  git -c user.email=agent@autoblog -c user.name="autoblog agent" commit -m "initial vault seed"

  # Bare repo = canonical remote
  git init --bare -b main /vault-remote.git
  git push /vault-remote.git main
  rm -rf /tmp/vault-seed

  # Working clone
  git clone /vault-remote.git /vault

  # Configure the agent's identity for its future vault commits
  git -C /vault config user.email "agent@autoblog"
  git -C /vault config user.name "autoblog agent"

  chown -R autoblog:autoblog /vault /vault-remote.git
fi
```

Idempotent: subsequent boots skip this entirely.

### Task 3 — vault-template files

**CREATE `vault-template/CLAUDE.md`:**

```markdown
# Vault schema

This is an agent-maintained personal knowledge base in the LLM Wiki pattern
(see docs/idea.md for the original concept). The wiki is organized by
**content type, not subject matter** — subject matter lives in wikilinks and
tags, so the graph can reshape itself without folder moves.

## Layout

- `raw/` — user-provided sources (articles, notes, PDFs, clippings, daily
  drops). The user writes here. The agent READS raw but never modifies it.
  Attachments go under `raw/assets/` (Obsidian Web Clipper default).
- `wiki/` — agent-authored markdown pages. Five content-type subdirs:
    - `wiki/daily/` — short dated entries. Daily updates, life updates,
      running notes, TILs. **One file per day: `YYYY-MM-DD.md`.** If the file
      exists, append a new section rather than creating a new file.
    - `wiki/notes/` — concept pages and learning material. Things being
      studied, frameworks, theories, takeaways from articles. Filename is a
      kebab-case slug of the concept (`rust-ownership.md`).
    - `wiki/ideas/` — longer-lived, evolving ideas the user wants to develop
      over time. Filename is a kebab-case slug of the idea.
    - `wiki/entities/` — people, organizations, tools, projects. Filename is
      a kebab-case slug of the entity name (`andrej-karpathy.md`).
    - `wiki/sources/` — per-source summaries. Every ingested raw file gets a
      matching page here. Filename: `YYYY-MM-DD-<slug>.md`. This is the
      agent's traceability record — any claim in the wiki should be one
      wikilink away from its origin source page.
- `log.md` — chronological record of what the agent has done (ingests, edits,
  lint passes). Append-only. The agent greps `log.md` to determine which raw
  files have already been ingested.
- `index.md` — catalog of wiki pages with one-line summaries, organized by
  content type (Daily / Notes / Ideas / Entities / Sources). Updated on every
  ingest.
- `.obsidian/` — Obsidian workspace metadata. Gitignored (each device has its
  own).
- `.trash/` — Obsidian's trash. Gitignored.

## Filing heuristic

When ingesting a raw source, the agent makes ONE judgment: which content type
is this? Almost always obvious from the raw material itself.

| Source looks like                              | Primary page                       | Plus                                   |
|------------------------------------------------|------------------------------------|----------------------------------------|
| Dated note, life update, TIL, daily thought    | `wiki/daily/<YYYY-MM-DD>.md` (append section if file exists) | + `wiki/sources/<date>-<slug>.md` |
| Article, book, learning material, concept      | `wiki/notes/<concept-slug>.md` (create or targeted-edit) | + `wiki/sources/<date>-<slug>.md` |
| Half-formed thought to develop                 | `wiki/ideas/<slug>.md` (create or targeted-edit) | + `wiki/sources/<date>-<slug>.md` |
| Mostly a source summary, no strong concept yet | `wiki/sources/<YYYY-MM-DD>-<slug>.md` alone, referenced from `index.md` | |

Regardless of primary page, the agent also creates or updates
`wiki/entities/` pages for any people/orgs/tools the source mentions
meaningfully. Cross-reference back to those entity pages via `[[wikilinks]]`.

An ingest typically touches multiple content types: an article on Rust
ownership creates `wiki/notes/rust-ownership.md` and
`wiki/sources/2026-04-19-rust-ownership.md`, and may update
`wiki/entities/some-author.md`.

## Conventions

- Wiki filenames: kebab-case. Daily files use `YYYY-MM-DD.md`; source files
  use `YYYY-MM-DD-<slug>.md`.
- Cross-references: `[[wikilinks]]` throughout. Obsidian resolves them across
  subdirs, so no paths needed.
- **Required frontmatter on every agent-authored wiki page:**
    ```yaml
    ---
    type: daily | note | idea | entity | source
    ai-generated: true
    sources:
      - raw/2026-04-19-karpathy-llm-wiki.md
    tags: [optional, list]
    ---
    ```
  `ai-generated: true` distinguishes agent output from anything the user
  writes directly in the wiki. `sources:` is the audit path — if a claim is
  surprising or feels wrong, follow `sources:` back to the raw file that
  produced it.
- Log entries: each starts `## [YYYY-MM-DD] <operation> | <short description>`
  so `grep "^## \[" log.md` returns a clean timeline.
- **No subject-matter folders.** No `wiki/tech/`, no `wiki/rust/`. Subject
  lives in wikilinks and tags. Folders signal content type only.

## Ingest workflow summary

Full procedure is in the agent's `ingest-source` skill. Summary:

1. `git pull --rebase` to catch any recent pushes from user devices.
2. Walk `raw/`, compare against `log.md` to find files not yet ingested.
3. For each new file: decide content type, create/update the primary page,
   always create the matching `wiki/sources/` page, update any entity pages
   that need it, update `index.md`, append to `log.md`.
4. `git add -A && git commit && git push`.

The agent always operates on the working clone at `/vault`; pushes flow
through to `/vault-remote.git`, which the user's devices sync from.

## Maps of Content (later, not now)

Once `wiki/` has ~50 pages, curated topic-level index pages can live under
`wiki/_maps/` (e.g., `_maps/learning.md` as a hand-curated entry point into
notes by subject). Premature at an empty vault — add when navigation actually
needs it.

## Lint

On user request, the agent audits the wiki for:

- Contradictions between pages (X said on one page, not-X on another)
- Stale claims (a newer source contradicts an older claim)
- Orphan pages (no inbound wikilinks)
- Important concepts mentioned but lacking their own page
- Missing cross-references
- Wiki pages missing `ai-generated:` or `sources:` frontmatter
- Subject-matter folders that have crept in under `wiki/` (none should exist)

Lint is manual; run when the wiki feels thick.
```

**CREATE `vault-template/log.md`:**

```markdown
# Log

Chronological record of vault operations. Append-only. The ingest skill reads
this to decide which raw sources have already been processed — a source is
considered ingested if its path appears in a `## [YYYY-MM-DD] ingest | <path>`
entry.

Entries format:

    ## [YYYY-MM-DD] <operation> | <short description>
    <optional body paragraph>

Operations: `ingest`, `re-ingest`, `edit`, `lint`, `roundup`.
```

**CREATE `vault-template/index.md`:**

```markdown
# Index

Catalog of wiki pages. Updated on every ingest. Sections match the content-type
subdirs under `wiki/`.

## Daily

*(none yet)*

## Notes

*(none yet)*

## Ideas

*(none yet)*

## Entities

*(none yet)*

## Sources

*(none yet)*
```

**CREATE `vault-template/.gitignore`:**

```
.obsidian/
.trash/
```

**CREATE empty `.gitkeep` files** in `vault-template/raw/` and in each of the five wiki subdirs: `vault-template/wiki/daily/`, `wiki/notes/`, `wiki/ideas/`, `wiki/entities/`, `wiki/sources/`. Git doesn't track empty directories, so each needs a `.gitkeep` to exist in the initial commit. The seed paths matter: the agent writes into them on first ingest without having to create the subdir.

### Task 4 — Update agent CLAUDE.md

Expand `agent-template/CLAUDE.md` for Phase 1c:

- Three roots now: `/agent`, `/site`, `/vault`.
- Git discipline: every vault-touching skill does `git -C /vault pull --rebase` before reading and `git -C /vault push` after committing. This keeps the agent and the user's devices in sync.
- Remind the agent that the user writes `raw/`; the agent writes everything else. If you find yourself modifying a file in `raw/`, stop — something is wrong.
- **Wiki layout**: `wiki/` is organized by content type, not subject matter — `wiki/daily/`, `wiki/notes/`, `wiki/ideas/`, `wiki/entities/`, `wiki/sources/`. Subject lives in `[[wikilinks]]` and tags. Do not create subject-matter subfolders. Full schema (filing heuristic, required frontmatter, conventions) is in `/vault/CLAUDE.md` — read it before the first ingest of a session.
- Every agent-authored wiki page must have frontmatter with `type:`, `ai-generated: true`, and a `sources:` list pointing back to the raw files that informed it.
- List the full skill set (now 9):
  - Site (from 1b): `deploy`, `rollback`, `publish-draft`, `update-home`, `new-page`, `discard-dev`.
  - Vault (new in 1c): `ingest-source`, `write-timeline-entry`, `weekly-roundup`.

### Task 5 — ingest-source skill (simplified)

**CREATE `agent-template/.claude/skills/ingest-source.md`:**

```markdown
---
name: ingest-source
description: Process raw sources into the wiki; update log.md and index.md.
when: User says "ingest", "process raw", "process new files", "catch up on raw"
---

This is the core wiki-maintenance skill. Based on Karpathy's LLM Wiki pattern:
drop a source into raw/, tell the agent to process it, the agent reads, writes
wiki pages, updates the index, and appends to the log.

## Hard rule

NEVER write, rename, or modify anything under `/vault/raw/`. Raw is read-only
by convention — the user is the only one who writes there. If you find yourself
about to touch `raw/`, stop.

## Steps

### 1. Sync

Before anything else:

    git -C /vault pull --rebase

This pulls in any recent pushes from the user's devices (phone, laptop, etc.).

### 2. Determine what's pending

A source is "already ingested" if its path appears in a line like
`## [YYYY-MM-DD] ingest | raw/<path>` in `/vault/log.md`. To find pending files:

    ls -R /vault/raw/                    # what files exist now
    grep -E "^## \[.*\] ingest \| raw/" /vault/log.md   # what's been ingested

Compute the set difference: files in raw/ that are NOT mentioned in the log.
Skip `.DS_Store`, anything under `assets/` unless it's the subject (see below),
and obvious junk.

Print a summary to the user before proceeding: "<N> files pending: <list>."

If the user pointed at a specific file ("ingest raw/foo.md"), process just that
one and don't try to catch up on everything.

### 3. Group notes with their attachments

Markdown notes often reference attachments (images, PDFs) via wikilinks like
`![[image.png]]` or markdown image links. When ingesting a note, also process
any referenced attachments in `raw/assets/` in the same pass — the note's context
gives the attachment meaning. The attachment's log entry references the parent
note.

Attachments with no referencing note are ingested as standalone sources.

### 4. Process each source

For each pending source:

a. Read the file (and any referenced attachments).
b. Extract entities, concepts, and facts. Decide the content type
   (daily / note / idea / source-only).
c. Create or update pages in `/vault/wiki/` by content type:
   - **Always** create `wiki/sources/<YYYY-MM-DD>-<slug>.md` — a summary of
     this specific raw file. This is the traceability record; every claim
     elsewhere should be reachable from here via wikilink.
   - Dated / life-update / TIL / daily-thought content →
     `wiki/daily/<YYYY-MM-DD>.md`. If the file already exists for that day,
     APPEND a section; do not overwrite.
   - Learning / concept / article content →
     `wiki/notes/<concept-slug>.md`. Create new or targeted-edit existing.
   - Half-formed idea to develop →
     `wiki/ideas/<slug>.md`. Create new or targeted-edit existing.
   - Any person/org/tool mentioned meaningfully →
     `wiki/entities/<slug>.md`. Create new or update with new context.
   - Use `[[wikilinks]]` for all cross-references (Obsidian resolves them
     across subdirs).
   - Every agent-authored page carries frontmatter:
     `type:`, `ai-generated: true`, `sources: [raw/...]`, optional `tags`.
   - Never create subject-matter subfolders (no `wiki/tech/`, no `wiki/rust/`).
d. Update `/vault/index.md`: add new pages under the matching section
   (Daily / Notes / Ideas / Entities / Sources).
e. Append to `/vault/log.md`:
       ## [YYYY-MM-DD] ingest | raw/<path>
       <1-2 sentence narrative of what was extracted and which wiki pages
        were created or updated>

### 5. Commit and push

    cd /vault
    git add -A
    git commit -m "ingest: <comma-separated basenames>"
    git push

### 6. Report to the user

Summary: "Ingested <N> sources. Created <M> new wiki pages, updated <K> existing.
See log.md for narrative."

## Re-ingest

If the user says "re-ingest raw/foo.md", treat it as a forced re-process:

1. Skip the pending-check (the user is overriding).
2. Run the same ingest steps.
3. Log entry: `## [YYYY-MM-DD] re-ingest | raw/foo.md` with a note on why
   (the user asked; or the content materially changed).

Do NOT try to compute a diff from previous versions. If the user needs that
level of sophistication, they'll tell you and we'll build it. For now: re-ingest
means "read the current file and fold it into the wiki."

## Batch handling

On "process all pending": do the detection once, show the list, then process one
source (or note-and-attachments group) at a time, committing between each.

If a single source fails partway (e.g. the file is corrupt): log a line
`## [YYYY-MM-DD] skip | raw/<path> — <reason>` with the reason and move on.
Commit what succeeded. Report which files failed at the end.

## Conventions the agent maintains

- Wiki subdirs are content-type, not subject-matter: `daily/`, `notes/`, `ideas/`, `entities/`, `sources/`.
- Wiki filenames: kebab-case. Daily: `YYYY-MM-DD.md`. Source: `YYYY-MM-DD-<slug>.md`.
- Required frontmatter: `type: daily | note | idea | entity | source`, `ai-generated: true`, `sources: [raw/...]`, optional `tags`.
- Wikilinks: `[[page-name]]` (Obsidian resolves across subdirs — no paths needed).
- Log entries: always start `## [YYYY-MM-DD] <op> | <subject>` so grep works.
- Index categories: Daily / Notes / Ideas / Entities / Sources.

## What NOT to do

- No chunk-level or sha-level tracking. The log is the record.
- No automatic ingest. This skill runs only when the user invokes it.
- No writes to raw/. Ever.
- No subject-matter subfolders under wiki/. Subject lives in wikilinks/tags.
- No rewriting whole wiki pages when a section-level edit will do.
- No creating a new `wiki/daily/<date>.md` if one already exists — APPEND a section.
- No agent-authored page without `ai-generated:` and `sources:` frontmatter.
- No skipping the pull-before-read or push-after-commit steps. Every run does both.
```

### Task 6 — write-timeline-entry skill

**CREATE `agent-template/.claude/skills/write-timeline-entry.md`:**

```markdown
---
name: write-timeline-entry
description: Draft a timeline post from recent vault activity.
when: User says "write a timeline entry", "write a post about X"
---

Timeline entries are short curated posts — not dumps of what the agent has done.
They go to /site/dev/src/content/timeline/<date>-<slug>.md with status: draft.

## Steps

1. `git -C /vault pull --rebase`  # sync vault first
2. Read /vault/log.md (recent entries) and the relevant wiki pages.
3. If the user gave a topic ("write about rust macros"):
     - Pull the relevant wiki pages.
     - Compose a 2-4 paragraph post. Voice: conversational, first-person,
       specific. Not a summary.
4. If the user said "what's interesting from this week":
     - Read log.md entries from the last 7 days.
     - Identify 2-4 themes. Do NOT enumerate every log line.
     - Draft a single post organized around the themes.
5. Write to /site/dev/src/content/timeline/<YYYY-MM-DD>-<slug>.md with:
     ---
     title: "<title>"
     date: <YYYY-MM-DD>
     status: draft
     ---
6. Commit on dev:
     cd /site/dev
     git add -A
     git commit -m "draft timeline: <slug>"
7. Tell the user to review the draft at http://localhost:4321/timeline/<slug>
   (or via the SSH tunnel in Phase 2). Suggest running `publish-draft` + `deploy`
   when they're happy.

## Non-goals

- Don't auto-publish. Status stays `draft` until the user says so.
- Don't touch /vault. This skill reads vault, writes site.
```

### Task 7 — weekly-roundup skill

**CREATE `agent-template/.claude/skills/weekly-roundup.md`:**

```markdown
---
name: weekly-roundup
description: Draft a timeline entry summarizing the last week's vault activity.
when: User says "weekly roundup", "what did I work on this week"
---

Like `write-timeline-entry`, but specifically week-windowed and reflective.

## Steps

1. `git -C /vault pull --rebase`
2. Read /vault/log.md entries from the last 7 days: `grep "^## \[" log.md`,
   filter by date, and read the associated narrative.
3. Also check `git -C /vault log --since="7 days ago" --oneline` for anything
   the log.md entries didn't fully capture.
4. Identify 2-4 themes. Skip pedestrian housekeeping.
5. Compose a single timeline entry: conversational, reflective, first-person.
   Point at interesting wiki pages via links (the site won't render them, but
   the draft text can reference them for your own record).
6. Write to /site/dev/src/content/timeline/<YYYY-MM-DD>-week-of-<start-date>.md
   with status: draft.
7. Commit on dev, report to user, suggest publish+deploy.

## Non-goals

- Don't include raw log lines. Narrative only.
- Don't auto-publish.
```

### Task 8 — docs/vault-sync.md

**CREATE `docs/vault-sync.md`:**

This is the user-facing guide for setting up Obsidian on each device. Cover:

**Overview section:**
- The vault is a git repo. The canonical copy is the bare repo at `/vault-remote.git` inside the autoblog container, reachable via SSH on port 2222.
- Every device (laptop, desktop, phone) is an independent git clone. The Obsidian Git plugin handles pull/push automatically.
- The autoblog agent is also a git client — it works in `/vault/` (a clone), pulls before reading, pushes after writing.
- Write pattern: you touch `raw/` (and only `raw/`); the agent touches everything else. This means real conflicts are rare.

**Laptop / desktop setup (macOS, Linux, Windows):**

```bash
# 1. Make sure your SSH key is in .env as SSH_PUBLIC_KEY (same key used for the
#    agent shell works for git too).

# 2. Clone the vault onto your laptop:
git clone ssh://autoblog@localhost:2222/vault-remote.git ~/Documents/autoblog-vault

# (For Phase 2 on a VPS, replace `localhost` with your VPS hostname.)

# 3. Open the folder in Obsidian: File → Open Vault → select ~/Documents/autoblog-vault.

# 4. Install the Obsidian Git plugin:
#    Settings → Community plugins → Browse → search "Obsidian Git" → Install + Enable.

# 5. Configure Obsidian Git:
#    - Commit message on auto-backup: "vault: {{date}}" (or similar).
#    - Auto-backup interval: 5 minutes.
#    - Pull on start: ON.
#    - Pull on auto-backup: ON.
#    That's enough — the plugin will now commit your changes and pull the agent's
#    changes on a timer.
```

**Phone setup (iOS):**

1. Install Obsidian Mobile from the App Store.
2. On the phone, generate an SSH key (via Blink Shell, Working Copy, or similar). Public key format `ssh-ed25519 …`.
3. Add that public key to your `.env`'s `SSH_PUBLIC_KEY` (append; each device needs its own key if you want per-device rotation — authorized_keys supports multiple lines). Re-run `docker compose up -d` so bootstrap refreshes `authorized_keys` with the new key set.
4. In Obsidian Mobile: Create a new vault in a local folder. Do NOT use iCloud sync.
5. Install Obsidian Git plugin (same search flow).
6. Configure the git remote inside Obsidian Git's plugin settings: URL `ssh://autoblog@<host>:2222/vault-remote.git`. Point the plugin at your private key file (stored in the app's sandboxed storage).
7. Initial pull: plugin runs pull-on-start; verify your vault content arrives.
8. Verify push: add a file under `raw/test.md` in Obsidian Mobile, wait for the auto-backup interval or trigger manually via the command palette (`Obsidian Git: Create backup and push`).

Note: iOS Obsidian Git setup is finickier than desktop. If you hit key-format or SSH config issues, the common fix is to re-export the private key in OpenSSH format (not PEM).

**Phone setup (Android):**

Same flow as iOS; keys are slightly easier to manage via Termux or the plugin's built-in key generator.

**Multi-device key management:**

Each device has its own SSH key. `authorized_keys` inside the container supports one key per line:

```bash
# in .env
SSH_PUBLIC_KEY="ssh-ed25519 AAAA...laptop
ssh-ed25519 BBBB...desktop
ssh-ed25519 CCCC...phone"
```

(The bootstrap script writes the `SSH_PUBLIC_KEY` env var directly to `authorized_keys`; newlines in the env var become newlines in the file.)

**Conflict handling:**

Your write pattern (only `raw/`) and the agent's write pattern (everything else) are disjoint, so conflicts are rare in practice. When they do happen, Obsidian Git surfaces them as merge conflicts. To resolve:

1. Open the conflicted file. Git conflict markers (`<<<<<<<`, `=======`, `>>>>>>>`) will be visible.
2. Edit to keep the content you want.
3. Commit and push.

If you're stuck and the conflict is in a wiki page (agent-authored territory), the cleanest reset is:

```bash
# on the device with the problem
git fetch origin
git reset --hard origin/main
```

This discards local changes in favor of what's on the server. Only do this on a device where you haven't made edits you care about.

**What's NOT covered here:**

- Obsidian Sync (the paid service). It's end-to-end encrypted and doesn't let the container participate — so it doesn't work for this architecture. Use Obsidian Git.
- Mutagen. Has no mobile client; not used by this architecture.

### Task 9 — Sanity check + validation

Run the validation loop below.

## Validation loop

```bash
# 1. Build still succeeds
docker compose build

# 2. Up and wait
docker compose up -d --wait
docker compose ps
# Expected: healthy

# 3. Bare repo + working clone exist
docker compose exec autoblog bash -c \
  "test -d /vault-remote.git && test -d /vault/.git && git -C /vault log --oneline"
# Expected: initial seed commit

# 4. Initial vault content is in place
docker compose exec autoblog ls /vault
# Expected: CLAUDE.md, log.md, index.md, raw/, wiki/, .gitignore, .git/

# 5. Clone from host (simulates a laptop/phone client)
rm -rf /tmp/vault-test-clone
git clone ssh://autoblog@localhost:2222/vault-remote.git /tmp/vault-test-clone \
  -o origin
ls /tmp/vault-test-clone
# Expected: vault content as expected

# 6. Push from the clone reaches the remote
cd /tmp/vault-test-clone
mkdir -p raw
echo "test note" > raw/hello.md
git add .
git -c user.email=test@local -c user.name=test commit -m "raw: hello"
git push
# Expected: successful push

# 7. Agent's working copy can see the pushed file after pull
docker compose exec autoblog su - autoblog -c \
  "cd /vault && git pull --rebase && ls raw/"
# Expected: hello.md listed

# 8. Ingest skill (manual)
# ssh in, start claude, say: "ingest raw/hello.md"
# Expected:
#   - agent pulls, reads hello.md, writes a wiki page, appends to log.md, commits, pushes.
#   - /vault/wiki/ contains new page
#   - /vault/log.md has a new "## [YYYY-MM-DD] ingest | raw/hello.md" line
# Verify push reached the bare remote:
git -C /tmp/vault-test-clone pull
cat /tmp/vault-test-clone/log.md
# Expected: the new log line is visible from the clone

# 9. Agent never writes to raw/ (spot check)
git -C /vault log --all -- raw/hello.md
# Expected: the only commit touching hello.md is the test clone's push,
# NOT a later agent commit.

# 10. Port bindings unchanged
lsof -iTCP -sTCP:LISTEN -P | grep -E ':(2222|4321|8080)'
# Expected: 127.0.0.1-bound only
```

## Final checklist

- [ ] `docker compose up -d --wait` healthy with the new volumes.
- [ ] `/vault-remote.git` is bare; `/vault` is a clone with `origin` pointing at it.
- [ ] Vault template seeded on first boot (CLAUDE.md, log.md, index.md, raw/, wiki/, .gitignore).
- [ ] SSH-based git clone from the host works.
- [ ] External push reaches the remote; agent `git pull` brings it in.
- [ ] Ingest skill pulls, reads, writes wiki/log, commits, pushes — never writes to raw/.
- [ ] Write-timeline-entry and weekly-roundup skills present, both pull vault before reading.
- [ ] `docs/vault-sync.md` has setup steps for laptop/desktop and phone (iOS + Android).
- [ ] `.obsidian/` and `.trash/` are gitignored in the vault.
- [ ] Multi-key support documented (multiple `ssh-ed25519` lines in `SSH_PUBLIC_KEY`).
- [ ] Port bindings still loopback-only.

## Anti-patterns to avoid

- Letting the agent write to `/vault/raw/`. It's read-only by convention. Enforced in the skill rules, not by filesystem ACL — review agent commits periodically.
- Skipping `git pull --rebase` before reading vault. Stale reads lead to duplicate work and spurious conflicts.
- Skipping `git push` after committing. The user's other devices stay behind.
- Re-introducing a `processed.md` manifest with sha tracking. `log.md` is the record. Add sha tracking only when you hit the pain.
- Auto-resolving merge conflicts in wiki pages. Surface them; let the user judge.
- Using a non-bare working directory as the git remote. Push semantics are weird there. Bare is correct.
- Using Mutagen. Has no mobile support; replaced by Obsidian Git.
- Using Obsidian Sync (the paid service) as the sync layer. End-to-end encrypted — the container can't participate. It would become a second source of truth fighting this one.
- Committing `.obsidian/`. Workspace state churns per device; it will cause constant spurious merges.

## Out of scope

- VPS deployment — **Phase 2**.
- Sha-level dedup / edit detection / processed.md manifest — deferred until genuine pain arises.
- Automatic ingest on raw/ write. Manual for now (principle: intentional).
- Vault search engine (qmd / MCP). Index + grep is enough at target scale.
- Auto-tagging or auto-categorization of wiki pages beyond what the ingest skill produces.
- Backup automation for the vault volume.

## Plan confidence

**8/10** for one-pass implementation. The git-over-SSH access is just standard git behavior on top of the sshd we already have. The vault-template + bare-repo + clone bootstrap is symmetric with the site bootstrap from 1b, so the pattern is proven. Risks:

- Obsidian Mobile SSH key setup is platform-fiddly. `docs/vault-sync.md` is the first line of defense; plan for one or two real-device iterations.
- The ingest skill is prose at this point. Expect refinement as you use it — that's the point of skills-as-files.
- First real-world conflict (user edits `raw/foo.md` on two devices before one pushes) will be informative; plan to document the resolution pattern you land on.
