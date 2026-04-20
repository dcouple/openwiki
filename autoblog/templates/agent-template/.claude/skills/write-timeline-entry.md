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
