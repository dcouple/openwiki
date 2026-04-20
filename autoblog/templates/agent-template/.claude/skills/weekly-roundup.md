---
name: weekly-roundup
description: Draft a timeline entry summarizing the last week's vault activity.
when: User says "weekly roundup", "what did I work on this week"
---

Like `write-timeline-entry`, but specifically week-windowed and reflective.

## Steps

1. `git -C /vault pull --rebase`
2. Read /vault/log.md entries from the last 7 days: `grep "^## \[" /vault/log.md`,
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
