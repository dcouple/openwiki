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
