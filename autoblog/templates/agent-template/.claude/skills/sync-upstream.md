---
name: sync-upstream
description: Merge shipped template changes (new skills, CLAUDE.md updates) into /agent interactively, without touching memory or local customizations.
when: User says "sync upstream", "pull new skills", "apply shipped changes"
---

Compares `/opt/autoblog/templates/agent-template/` (latest shipped, refreshed
every image rebuild) against `/agent/` (the live volume) and interactively
applies accepted changes. NEVER touches `/agent/.claude/memory/`. NEVER deletes
a file that exists only in `/agent/`.

1. `cd /agent`

2. Run the diff, post-filtering memory paths (portable on BSD and GNU diff —
   do NOT use `--exclude-dir`, that is GNU-only):

     diff -rq /opt/autoblog/templates/agent-template/ /agent/ \
       | grep -Ev '/\.claude/memory/'

   The regex matches BOTH "Only in .../.claude/memory: MEMORY.md" and
   "Files .../.claude/memory/MEMORY.md and .../.claude/memory/MEMORY.md differ".

3. Parse the output into three buckets:

   - NEW_UPSTREAM: lines starting with `Only in /opt/autoblog/templates/agent-template/...`
       (upstream shipped something new — can be a file OR a directory).
   - LOCAL_ONLY:   lines starting with `Only in /agent/...`
       (user customization — REPORT ONLY, never touch).
   - DIFFERS:      lines starting with `Files ... and ... differ`
       (same path on both sides, contents differ).

   Do NOT try to classify DIFFERS further. `/agent` is not a git repo, so there
   is no reliable signal for "only upstream changed" vs "user also edited".
   Treat all DIFFERS uniformly: show diff, then ask.

4. Print a summary grouped by bucket. Example:

   New upstream (3):
     .claude/skills/sync-upstream.md
     .claude/skills/new-skill.md
     .claude/agents/             (directory)

   Changed (2):
     .claude/skills/deploy.md
     CLAUDE.md

   Local only, you keep these (1):
     .claude/skills/my-custom-skill.md

5. For each item in NEW_UPSTREAM and DIFFERS, ask the user. Offer:

     accept upstream / keep local / show (diff or contents) / skip

   - For DIFFERS items, show the diff BEFORE the first ask so the user has
     context:  `diff -u /agent/<path> /opt/autoblog/templates/agent-template/<path>`
   - For NEW_UPSTREAM items, offer "show contents" (use the Read tool to
     display the file, or `ls` + Read for a directory's contents).

   Apply decisions:
   - accept NEW_UPSTREAM:
       `cp -r /opt/autoblog/templates/agent-template/<path> /agent/<path>`
       (cp -r works for both files and directories; `diff -rq` "Only in" lines
        can name either.)
   - accept DIFFERS:
       `cp /opt/autoblog/templates/agent-template/<path> /agent/<path>`
       (always a file in this bucket.)
   - keep local:   no-op.
   - skip:         no-op, continue.

6. EXTRA CAUTION for anything under `.claude/` (memory already filtered) and
   for `CLAUDE.md` at the agent root: these are your own operating instructions.
   Before applying an accept decision on one of these paths, show the diff (or
   file contents for NEW_UPSTREAM) one more time and ask:

     "I'm about to overwrite <path>, which shapes my behavior. Confirm?"

   Do not require extra confirmation for paths outside `.claude/` and `CLAUDE.md`.

7. LOCAL_ONLY entries are reported but NEVER modified or deleted. If upstream
   removed a file that still exists locally, the local copy stays. If the user
   wants it gone, they delete it manually.

8. After all items are processed, report:

     "Synced N file(s). Skipped M. Local-only files untouched."

Safety:
- NEVER modify anything under `/agent/.claude/memory/`. That is the user's
  accumulated private state; it is never upstreamed.
- NEVER delete a file that exists only in `/agent/`. LOCAL_ONLY is untouched.
- NEVER auto-apply. Every overwrite needs explicit per-item user approval.
- ALWAYS show diff (or contents) and re-confirm before overwriting anything
  under `/agent/.claude/` or `/agent/CLAUDE.md`.
- `/agent` is NOT a git repo. Do not run `git log`, `git diff`, or any other
  git command inside `/agent` to reason about history.
- Site-template sync (`/site/prod`, `/site/dev`) is OUT OF SCOPE for this skill.
  If asked, say: "site template sync is not handled by this skill."
