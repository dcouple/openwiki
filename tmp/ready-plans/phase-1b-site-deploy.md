# autoblog Phase 1b — Astro Site, Worktrees, Deploy

## Overview

Adds the public site on top of the 1a runtime. At the end of this phase:

- `/site/repo.git` is a bare git repo; `/site/prod` (branch `main`) and `/site/dev` (branch `dev`) are linked worktrees.
- Astro dev server runs continuously inside the container on port 4321, serving `/site/dev/` (shows drafts).
- Caddy serves `/site/prod/dist/` (published only) at `http://localhost:8080`.
- The agent has skills for `deploy`, `rollback`, `publish-draft`, `update-home`, `new-page`, `discard-dev`.
- Deploy copies `dist/` from dev to prod rather than rebuilding twice — faster, identical output.
- `status: draft | published` frontmatter controls visibility at every `getCollection` call site.

No vault, no ingest yet. That's 1c.

## Why this order

1a gave us a working runtime. Layering the site on top before the vault means we can validate the draft-vs-published publishing model and the deploy/rollback flow in isolation — with hand-authored timeline entries — before introducing the much larger ingest surface. If the deploy pipeline has a bug, we want to find it here, not while debugging a misbehaving ingest.

## Prerequisite

Phase 1a is complete and its validation checklist passes. This phase extends those files; it does not rewrite them.

## Success criteria

- [ ] `docker compose build` still succeeds with the new template bundle.
- [ ] `docker compose up -d --wait` brings services healthy; first boot takes 3–10 min (npm install + initial build). Healthcheck tolerates that.
- [ ] `/site/repo.git` exists and is bare; `/site/prod` (main) and `/site/dev` (dev) are worktrees backed by it.
- [ ] `curl http://localhost:4321` returns Astro dev HTML (drafts visible).
- [ ] `curl http://localhost:8080` returns Astro prod HTML (drafts hidden).
- [ ] SSH in, run `claude`, say "deploy" → agent runs the deploy skill, prod updates, Caddy serves the new build.
- [ ] Rollback skill runs `git revert` on main and re-copies dist.
- [ ] Publishing a draft (`status: draft → published`) and re-deploying makes the page visible on `:8080`.
- [ ] All `getCollection` calls filter by status in production mode.
- [ ] Port bindings remain loopback-only (including the new 4321).

## Files created or changed in this phase

```
/Users/tbrownio/repos/autoblog/
├── compose.yml                          ← UPDATE: add DEV_BIND port, site volumes, relax healthcheck
├── Caddyfile                            ← UPDATE: point at /srv/site/prod/dist
├── .env.example                         ← UPDATE: add DEV_BIND
│
├── autoblog/
│   ├── Dockerfile                       ← UPDATE: add start-stop-daemon dependency if not present
│   ├── entrypoint.sh                    ← UPDATE: launch astro dev in background after bootstrap
│   └── bootstrap-volumes.sh             ← UPDATE: site seeding + worktree setup
│
├── agent-template/
│   ├── CLAUDE.md                        ← UPDATE: document /site roots, dev/prod worktrees, deploy flow
│   └── .claude/skills/                  ← NEW
│       ├── deploy.md
│       ├── rollback.md
│       ├── publish-draft.md
│       ├── update-home.md
│       ├── new-page.md
│       └── discard-dev.md
│
├── site-template/                       ← NEW (seeded into /site on first boot)
│   ├── package.json
│   ├── astro.config.mjs
│   ├── tsconfig.json
│   ├── public/
│   │   └── favicon.svg
│   └── src/
│       ├── content.config.ts
│       ├── styles/global.css
│       ├── layouts/
│       │   ├── BaseLayout.astro
│       │   └── PostLayout.astro
│       ├── home.md                      # NOT in a collection — direct-imported by index.astro
│       ├── pages/
│       │   ├── index.astro              # → /
│       │   ├── [slug].astro             # → /<slug> for standalone pages
│       │   ├── timeline/index.astro     # → /timeline
│       │   └── timeline/[slug].astro    # → /timeline/<slug>
│       └── content/
│           ├── timeline/.gitkeep
│           └── pages/about.md           # → /about (status: published)
│
└── static-template/                     ← REMOVED (site-template supersedes the placeholder)
```

`autoblog_static` volume is removed from `compose.yml`; Caddy now reads `autoblog_site` instead.

## Reference material

```yaml
- url: https://docs.astro.build/en/guides/content-collections/
  why: Content collections v5 API (glob loader + zod schema). No auto-draft filtering — filter explicitly at every getCollection call.

- url: https://docs.astro.build/en/reference/modules/astro-content/#getcollection
  why: Filter callback signature: `({ data }) => boolean`. Use `import.meta.env.PROD` to branch on dev vs prod builds.

- url: https://git-scm.com/docs/git-worktree
  why: Worktrees share a single .git directory (or bare repo). Two worktrees on two branches = one history, two checkouts.

- file: /Users/tbrownio/repos/autoblog/docs/autoblog-overview.md
  why: Architecture reference. Deploy model, publishing model.
```

## Known gotchas

```
# CRITICAL: Astro 5 does NOT auto-filter drafts. Must filter at every getCollection call:
#   const entries = await getCollection('timeline', ({ data }) =>
#     import.meta.env.PROD ? data.status === 'published' : true
#   );
# Apply in pages, layouts, and any component that queries a collection. Missing one = draft leaks to prod.

# CRITICAL: `status` is a string enum ('draft' | 'published'), NOT the legacy boolean `draft` field.
# Clearer semantics; schema enforces via zod enum.

# CRITICAL: Worktree creation cannot happen from inside a compose build. Must be in
# bootstrap-volumes.sh at first-boot. Use a BARE repo at /site/repo.git as the shared
# object store; both worktrees point at it. This is the only correct way to have two
# worktrees on different branches share one history.

# CRITICAL: Astro dev server needs --host 0.0.0.0 inside the container so the Docker
# port publish reaches it. Do NOT bind it to 127.0.0.1 inside the container — Docker
# would fail to forward.

# CRITICAL: First-boot time is 3-10 min (npm install × 2 + initial astro build).
# Healthcheck retries must cover it: start_period 5m, retries 60 at 10s interval.
# Entrypoint should log progress loudly so the user knows it's working, not hung.

# CRITICAL: Deploy skill copies /site/dev/dist → /site/prod/dist, not rebuilds in prod.
# The dev build is the gate; the prod build would be byte-identical given the same
# source tree after merge. Copying saves 2-5 min per deploy. Merge commit on main
# still records the deploy in git history.

# CRITICAL: src/home.md lives at src/home.md, NOT src/content/home.md. It belongs to
# no collection; it's direct-imported by src/pages/index.astro via Astro's native .md
# import (default export = component; named export `frontmatter`).

# CRITICAL: Reserved slugs for standalone pages — 'timeline' and 'index' collide with
# static routes. The new-page skill must check and refuse. Astro build also errors on
# a collision as a safety net.

# CRITICAL: `discard-dev` resolves the target commit via the prod worktree's HEAD,
# not by name: `git reset --hard "$(git -C /site/prod rev-parse main)"`. In a linked
# worktree, `main` is another worktree's checked-out branch and this path is unambiguous.
```

## Architecture changes (delta over 1a)

```
autoblog container processes (entrypoint order):
  1. bootstrap-volumes.sh (idempotent; now also seeds /site + creates worktrees)
  2. astro dev (bg via start-stop-daemon; runs in /site/dev; always-on)
  3. sshd -D (fg)

New port mapping:
  ${DEV_BIND:-127.0.0.1}:4321:4321

New volume:
  autoblog_site → /site  (replaces autoblog_static; Caddy now reads /site/prod/dist)

Caddy root:
  /srv/site/prod/dist  (mounted from autoblog_site:/srv/site:ro)
```

## Implementation tasks

### Task 1 — Update compose.yml

**MODIFY `compose.yml`:**

- Remove `autoblog_static` volume from the autoblog service and from the top-level `volumes:` map.
- Add `autoblog_site:/site` to the autoblog service.
- Add port mapping `"${DEV_BIND:-127.0.0.1}:4321:4321"` to autoblog.
- Relax healthcheck on autoblog: `retries: 60`, `start_period: 5m` (covers first-boot npm install + build).
- Change caddy's mount: remove `autoblog_static:/srv/static:ro`, add `autoblog_site:/srv/site:ro`.
- Add `autoblog_site` to top-level `volumes:`.

### Task 2 — Update .env.example

Add `DEV_BIND=127.0.0.1` with comment: "ALWAYS loopback — never public; Phase 2 reaches dev via SSH -L."

### Task 3 — Update Caddyfile

```caddy
{$DOMAIN:localhost} {
    root * /srv/site/prod/dist
    file_server
    try_files {path} {path}/ /index.html
    encode gzip
    header / Cache-Control "public, max-age=300"
}
```

### Task 4 — Update Dockerfile

Add `start-stop-daemon` if not already present in dependencies (it's in debian's `dpkg` package normally; verify). No other Dockerfile changes — Node and Astro install into the site volume at runtime, not the image.

Add `rsync` package (needed by the deploy skill to copy `dist/`). `apt install -y rsync` in the existing `apt-get install` block.

### Task 5 — Update entrypoint.sh

```bash
#!/bin/bash
set -euo pipefail

echo "[autoblog] bootstrap starting…"
/opt/autoblog/bin/bootstrap-volumes.sh
echo "[autoblog] bootstrap complete"

# Start Astro dev server in the background
echo "[autoblog] starting astro dev on :4321"
start-stop-daemon --start --background --chuid autoblog:autoblog \
  --chdir /site/dev \
  --make-pidfile --pidfile /var/run/astro-dev.pid \
  --startas /bin/bash -- \
  -c "exec npm run dev -- --host 0.0.0.0 --port 4321 >> /var/log/astro-dev.log 2>&1"

echo "[autoblog] starting sshd"
exec /usr/sbin/sshd -D -e
```

### Task 6 — Update bootstrap-volumes.sh

Add the site-seeding block after agent seeding and before the readiness marker:

```bash
TEMPLATES=/opt/autoblog/templates

# Seed /site + create bare repo + two worktrees on first boot
if [ ! -d /site/repo.git ]; then
  echo "[bootstrap] seeding /site (bare repo + prod/dev worktrees)"

  # Build the initial commit in a scratch dir
  rm -rf /tmp/site-seed
  mkdir -p /tmp/site-seed
  cp -r "$TEMPLATES/site-template/." /tmp/site-seed/
  cd /tmp/site-seed
  git init -b main
  git add .
  git -c user.email=agent@autoblog -c user.name="autoblog agent" commit -m "initial site seed"

  # Bare repo owns the object store
  git init --bare -b main /site/repo.git
  git push /site/repo.git main
  rm -rf /tmp/site-seed

  # Both worktrees live outside the bare repo dir
  git -C /site/repo.git worktree add /site/prod main
  git -C /site/repo.git worktree add -b dev /site/dev main

  # Install node modules in both worktrees
  echo "[bootstrap] npm install in /site/dev (first run — several minutes)…"
  (cd /site/dev && npm install) 2>&1 | sed 's/^/  [dev] /'
  echo "[bootstrap] npm install in /site/prod…"
  (cd /site/prod && npm install) 2>&1 | sed 's/^/  [prod] /'

  # Initial prod build so Caddy has something to serve on first boot
  echo "[bootstrap] initial astro build in /site/prod…"
  (cd /site/prod && npm run build) 2>&1 | sed 's/^/  [build] /'

  chown -R autoblog:autoblog /site
fi
```

The idempotency check (`[ ! -d /site/repo.git ]`) means subsequent boots skip this entire block. Existing node_modules and dist survive.

Remove the old `/srv/static` seeding block — it's replaced.

### Task 7 — site-template files

**CREATE `site-template/package.json`:**
```json
{
  "name": "autoblog-site",
  "type": "module",
  "scripts": {
    "dev": "astro dev",
    "build": "astro build",
    "preview": "astro preview"
  },
  "dependencies": {
    "astro": "^5",
    "@astrojs/mdx": "^4"
  }
}
```

Version floor targets Astro 5 (content collections v2 API). Verify exact minor at implementation time.

**CREATE `site-template/astro.config.mjs`:**
```javascript
import { defineConfig } from 'astro/config';
import mdx from '@astrojs/mdx';

export default defineConfig({
  output: 'static',
  integrations: [mdx()],
});
```

**CREATE `site-template/tsconfig.json`:**
```json
{ "extends": "astro/tsconfigs/strict" }
```

**CREATE `site-template/src/content.config.ts`:**
```typescript
import { defineCollection, z } from 'astro:content';
import { glob } from 'astro/loaders';

const statusSchema = z.enum(['draft', 'published']).default('draft');

const timeline = defineCollection({
  loader: glob({ pattern: '**/*.md', base: './src/content/timeline' }),
  schema: z.object({
    title: z.string(),
    date: z.coerce.date(),
    status: statusSchema,
  }),
});

const pages = defineCollection({
  loader: glob({ pattern: '**/*.md', base: './src/content/pages' }),
  schema: z.object({
    title: z.string(),
    status: statusSchema,
  }),
});

export const collections = { timeline, pages };
```

**CREATE `site-template/src/styles/global.css`:**

Minimal typography. System font stack, max-width ~70ch, responsive, readable on mobile. No framework.

**CREATE `site-template/src/layouts/BaseLayout.astro`:**

HTML shell. Nav links: `/`, `/timeline`, `/about`. Slot for content. Imports `global.css`. Do not add a `/pages` link — there is no `/pages` index.

**CREATE `site-template/src/layouts/PostLayout.astro`:**

Wraps `BaseLayout`. Renders frontmatter title, date (for timeline entries), and body.

**CREATE `site-template/src/pages/index.astro`:**

```astro
---
import { getCollection } from 'astro:content';
import BaseLayout from '../layouts/BaseLayout.astro';
import { Content as HomeContent, frontmatter as homeFront } from '../home.md';

const entries = await getCollection('timeline', ({ data }) =>
  import.meta.env.PROD ? data.status === 'published' : true
);
const latest = entries
  .sort((a, b) => b.data.date.getTime() - a.data.date.getTime())
  .slice(0, 5);
---
<BaseLayout title={homeFront.title}>
  <HomeContent />
  <h2>Lately</h2>
  <ul>
    {latest.map(e => (
      <li><a href={`/timeline/${e.id}`}>{e.data.title}</a> — {e.data.date.toLocaleDateString()}</li>
    ))}
  </ul>
</BaseLayout>
```

**CREATE `site-template/src/pages/timeline/index.astro`:**

`getCollection('timeline', …)` with the draft filter; sort desc; render full list.

**CREATE `site-template/src/pages/timeline/[slug].astro`:**

`getStaticPaths` from `getCollection('timeline', …draft-filter…)`. Render with `PostLayout`.

**CREATE `site-template/src/pages/[slug].astro`:**

`getStaticPaths` from `getCollection('pages', …draft-filter…)`. Serves standalone pages at the site root: `/about`, etc. Render with `PostLayout`.

**CREATE `site-template/src/home.md`:**

```markdown
---
title: "Home"
---

Welcome. I'm the agent-maintained site for [your name]. Below: what I've been up to lately.
```

No `status` field — `home.md` is always rendered (it's not a collection entry).

**CREATE `site-template/src/content/timeline/.gitkeep`** (empty).

**CREATE `site-template/src/content/pages/about.md`:**
```markdown
---
title: "About"
status: published
---

Placeholder. Ask the agent to rewrite this with content from the vault.
```

**CREATE `site-template/public/favicon.svg`:**

Minimal "A" glyph inline SVG.

### Task 8 — Update agent CLAUDE.md

Expand `agent-template/CLAUDE.md` to cover the site:

- Three filesystem roots in Phase 1b: `/agent` (your config), `/site` (the site — prod + dev worktrees; bare repo at `/site/repo.git`), and (coming in 1c) `/vault`.
- Site publishing model: `status: draft | published` frontmatter; every `getCollection` filters on `import.meta.env.PROD ? published-only : all`.
- Deploy model: edits happen on `dev`; `deploy` skill merges `dev` → `main` and copies `dist`.
- Git discipline: you own git operations in `/site`. Users say "deploy"; you translate to git + rsync.
- List available skills (names + one-line triggers): deploy, rollback, publish-draft, update-home, new-page, discard-dev.

### Task 9 — Site skills

**CREATE `agent-template/.claude/skills/deploy.md`:**

```markdown
---
name: deploy
description: Merge dev into main, copy dist, serve new version.
when: User says "deploy", "ship", "publish the site", "push to prod"
---

Preconditions: /site/prod is on branch `main`; /site/dev is on branch `dev`.

1. `cd /site/dev`
2. Stage and commit any pending changes on dev:
     git add -A
     git diff --cached --quiet || git commit -m "wip: pre-deploy"
3. SANITY-CHECK BUILD: `npm run build` in /site/dev.
   If it fails: STOP and report the error to the user. Do NOT touch main.
4. `cd /site/prod`
5. Merge dev → main: `git merge dev --no-edit --no-ff`
   (no-ff keeps each deploy as a distinct merge commit in history)
6. Copy the built dist from dev to prod:
     rsync -a --delete /site/dev/dist/ /site/prod/dist/
   (dev and prod share the same source tree after the merge, so dev's dist
   is byte-identical to what a prod rebuild would produce. We copy to save
   time; the merge commit on main still records the deploy in git history.)
7. Report: "Deployed. Commit: <prod HEAD sha>. <N> files in dist."

Safety:
- Do NOT skip the build in step 3. It is the gate.
- Do NOT delete /site/prod/dist before copy — rsync --delete handles it atomically.
```

**CREATE `agent-template/.claude/skills/rollback.md`:**

```markdown
---
name: rollback
description: Undo the last deploy by reverting main; do not rewrite history.
when: User says "roll back", "undo last deploy", "revert"
---

1. `cd /site/prod`
2. Show the last 5 commits: `git log -n 5 --oneline main`
3. Revert HEAD: `git revert --no-edit HEAD`
   (creates a NEW commit that undoes the last one; audit-friendly, safe)
4. Rebuild prod's dist from the current prod source (which is now the pre-revert tree):
     cd /site/prod && npm run build
5. Report: "Reverted commit <sha>. New HEAD: <new sha>."

For multi-deploy rollback: `git revert --no-edit HEAD~N..HEAD` and rebuild. Ask the user first.

Note: this does NOT touch /site/dev. If the user also wants dev reset, suggest the `discard-dev` skill.
```

**CREATE `agent-template/.claude/skills/publish-draft.md`:**

```markdown
---
name: publish-draft
description: Flip a timeline entry or page from draft to published on dev.
when: User says "publish <slug>", "mark <post> as published"
---

1. Locate the file: ask the user if unclear; otherwise grep /site/dev/src/content/ for the slug.
2. Edit the frontmatter: change `status: draft` to `status: published`.
3. Commit on dev: `cd /site/dev && git add -A && git commit -m "publish: <slug>"`.
4. Recommend running the `deploy` skill next.
```

**CREATE `agent-template/.claude/skills/update-home.md`:**

```markdown
---
name: update-home
description: Edit the site home page content.
when: User says "update the home page", "change the intro"
---

The home page body lives at /site/dev/src/home.md (NOT /site/dev/src/content/home.md — home is
outside the content-collections tree because it belongs to no collection and is direct-imported
by src/pages/index.astro).

1. Read the current content.
2. Apply the user's requested edit. Preserve the `title` frontmatter field.
3. Commit on dev: `cd /site/dev && git add src/home.md && git commit -m "home: <short desc>"`.
```

**CREATE `agent-template/.claude/skills/new-page.md`:**

```markdown
---
name: new-page
description: Create a standalone page (about, essay, landing).
when: User says "create a new page for X", "add a page about Y"
---

Standalone pages live at /site/dev/src/content/pages/<slug>.md and serve at /<slug>.

1. Determine the slug. Ask the user if not clear.
2. REFUSE reserved slugs: "timeline" (collides with /timeline), "index" (collides with /).
   Ask for a different name.
3. Create the file with frontmatter:
     title: <user's title>
     status: draft
4. Write the body from vault content (once vault exists in 1c) or from a user-supplied prompt.
5. Commit on dev: `git add -A && git commit -m "new page: <slug>"`.
```

**CREATE `agent-template/.claude/skills/discard-dev.md`:**

```markdown
---
name: discard-dev
description: Throw away uncommitted and committed changes on dev; reset to main.
when: User says "throw away dev changes", "reset dev", "start over on dev"
---

Dev and prod are linked worktrees of the shared bare repo at /site/repo.git. `main` is prod's
checked-out branch, so we resolve the target commit via prod's HEAD (unambiguous for linked worktrees).

1. `cd /site/dev`
2. `git fetch --all`   # no-op with a local bare repo, safe to keep for symmetry
3. `git reset --hard "$(git -C /site/prod rev-parse main)"`
4. `git clean -ffd`    # remove untracked files + dirs

Report:
- Commits discarded (list from old HEAD to new HEAD)
- Untracked files removed
```

### Task 10 — Sanity check + validation

Run the validation loop below end-to-end.

## Validation loop

```bash
# 1. Compose still resolves
docker compose config > /dev/null

# 2. Build succeeds with new templates
docker compose build

# 3. Up and wait — first boot is 3-10 min
docker compose up -d --wait
docker compose ps
# Expected: autoblog healthy, caddy running

# 4. Ports still loopback-only (now including 4321)
lsof -iTCP -sTCP:LISTEN -P | grep -E ':(2222|4321|8080)'
# Expected: every line 127.0.0.1:*

# 5. /site layout is correct
docker compose exec autoblog bash -c \
  "test -d /site/repo.git && git -C /site/repo.git worktree list"
# Expected: bare repo + /site/prod [main] + /site/dev [dev]

# 6. Dev server shows drafts
curl -sf http://localhost:4321 | head -20
# Expected: HTML including the placeholder "about" page (published) and any draft content

# 7. Prod serves published-only
curl -sf http://localhost:8080 | head -20
# Expected: HTML including "about" (status: published); no drafts

# 8. Deploy skill works (manual)
#   ssh in, start claude, say: "create a new page called 'hello'"
#   then: "publish hello"
#   then: "deploy"
# Expected:
#   - hello page exists on dev at /site/dev/src/content/pages/hello.md
#   - status flipped to published, committed on dev
#   - main merged, dist copied, curl :8080/hello returns the page

# 9. Rollback skill works (manual)
#   after a deploy, say "roll back"
# Expected:
#   - git revert commit appears in /site/prod on main
#   - /site/prod/dist is rebuilt from the pre-deploy tree
#   - curl :8080/hello returns 404 (or previous state)

# 10. Dev-server loudness — bootstrap progress logged
docker compose logs autoblog | grep -E "bootstrap|astro|npm install"
# Expected: readable progress messages
```

## Final checklist

- [ ] `docker compose config` passes; `build` succeeds.
- [ ] Healthy services after `up -d --wait` (first boot 3–10 min; healthcheck tolerates it).
- [ ] `/site/repo.git` + `/site/prod` (main) + `/site/dev` (dev) present.
- [ ] Astro dev on `:4321` serves drafts; Caddy on `:8080` serves prod (no drafts).
- [ ] All six site skills present at `/agent/.claude/skills/`.
- [ ] Deploy skill merges and rsync-copies dist — does NOT rebuild prod.
- [ ] Rollback uses `git revert` (not `reset --hard`).
- [ ] Reserved slug guard active in `new-page`.
- [ ] `src/home.md` lives at `src/home.md` (NOT under `src/content/`).
- [ ] Port 4321 bound to 127.0.0.1 only.
- [ ] Agent `CLAUDE.md` documents the /site roots and deploy/rollback flow.

## Anti-patterns to avoid

- Auto-filtering drafts via collection config. Astro 5 does not support it; filter at every `getCollection`.
- Using the legacy boolean `draft` frontmatter field. Use the `status` enum.
- Rebuilding prod in the deploy skill. Copy from dev's dist — same tree, byte-identical output.
- Skipping the dev build in deploy. It is the gate — prod cannot regress from a bad edit.
- Putting `src/home.md` inside `src/content/`. It's not a collection entry.
- Letting a user create a page named `timeline` or `index`.
- Resolving `main` by name inside `/site/dev`. Use `git -C /site/prod rev-parse main`.
- Running `git reset --hard` for rollback. Use `git revert` — history is preserved.
- Auto-starting astro with `&` in bash instead of `start-stop-daemon`. Backgrounded shell jobs don't survive in PID 1 context reliably; use a proper daemon launcher.

## Out of scope

- Vault + ingest + Obsidian Git setup — **Phase 1c**.
- VPS deployment — **Phase 2**.
- Site search, richer collections, pagination, RSS — room later, not now.
- Scheduled publishing (frontmatter `publishAt`), unpublishing flow — not yet.

## Plan confidence

**8/10** for one-pass implementation. The delta is mostly Astro scaffold + git-worktree bootstrap + six small skills. Non-trivial because:
- Worktree + bare-repo sequencing must succeed first-boot or you're debugging a half-initialized volume.
- First-boot time (3–10 min) can mimic a hang. Loud progress logging mitigates.
- Astro 5's `glob()` + `status` enum combination may need one syntax tweak at implementation time.

No architectural risk. The likely corrections are single-line fixes.
