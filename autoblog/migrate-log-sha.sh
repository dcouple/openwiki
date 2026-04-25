#!/bin/bash
# One-shot first-run backfill of sha:<prefix> suffixes on pre-existing log
# entries. Idempotent: marker file short-circuits re-runs; awk also skips
# lines that already carry a sha suffix.
set -uo pipefail

MARKER=/vault/.ingest-migration-done
[ -f "$MARKER" ] && exit 0

# log.md may not exist on a fresh vault — nothing to migrate.
[ -f /vault/log.md ] || { touch "$MARKER"; exit 0; }

awk '
  /^## \[.*\] (ingest|re-ingest) \| raw\// {
    if ($0 ~ / sha:[0-9a-f]+$/) { print; next }
    idx = index($0, "| raw/")
    path = substr($0, idx + 2)
    full = "/vault/" path
    cmd = "[ -f \"" full "\" ] && sha256sum \"" full "\" | cut -c1-12 || true"
    cmd | getline sha
    close(cmd)
    if (sha ~ /^[0-9a-f]+$/) print $0 " sha:" sha
    else print $0
    next
  }
  { print }
' /vault/log.md > /vault/log.md.tmp && mv /vault/log.md.tmp /vault/log.md

touch "$MARKER"
