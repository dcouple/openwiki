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

For auto-loop re-ingest, find the existing wiki/sources/<date>-<slug>.md
whose frontmatter `sources:` list includes the raw path being re-processed,
and update that file in place. Do not create a new dated file. The date
in the filename reflects first ingest, not the re-ingest.

## Batch handling

On "process all pending": do the detection once, show the list, then process one
source (or note-and-attachments group) at a time, committing between each.

If a single source fails partway (e.g. the file is corrupt): log a line
`## [YYYY-MM-DD] skip | raw/<path> — <reason>` with the reason and move on.
Commit what succeeded. Report which files failed at the end.

## Auto-ingest contract

When invoked by the auto-ingest loop (not by a user), the prompt contains
an explicit list of files, each annotated with (sha:<12hex>, op:new|reingest).
Behavior in this mode:

1. Do NOT scan raw/ yourself — use exactly the provided list, in order.
2. op:new  → normal ingest per Steps above.
   op:reingest → FIND the existing wiki/sources page whose frontmatter
   `sources:` list includes this raw path, UPDATE it in place (do not create
   a new dated file), and revise dependent entity/concept pages as needed.
3. Every log entry you append MUST end with ` sha:<prefix>` using exactly
   the 12-char prefix from the prompt. Example:
       ## [YYYY-MM-DD] ingest | raw/foo.md sha:abc123def456
       ## [YYYY-MM-DD] re-ingest | raw/foo.md sha:789abc012345
   The loop uses this suffix to dedupe future scans. Omitting it causes
   infinite re-processing.

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
- Omit the ` sha:<prefix>` suffix on log entries. The auto-ingest loop depends on it.
