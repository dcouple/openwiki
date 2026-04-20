# Log

Chronological record of vault operations. Append-only. The ingest skill reads
this to decide which raw sources have already been processed — a source is
considered ingested if its path appears in a `## [YYYY-MM-DD] ingest | <path>`
entry.

Entries format:

    ## [YYYY-MM-DD] <operation> | <short description>
    <optional body paragraph>

Operations: `ingest`, `re-ingest`, `edit`, `lint`, `roundup`.
