#!/bin/bash
# set -uo pipefail, NOT -e — loop must survive individual batch failures
set -uo pipefail

POLL_INTERVAL="${INGEST_POLL_INTERVAL:-300}"
STABILITY_SECS="${INGEST_STABILITY_SECS:-60}"
BATCH_BYTES="${INGEST_BATCH_BYTES:-200000}"
MAX_BATCHES_PER_WAKE="${INGEST_MAX_BATCHES_PER_WAKE:-50}"
ENABLED="${INGEST_ENABLED:-1}"
FAILURE_BACKOFF_SECS=3600

# Must be verified against the installed `claude --help` output; newer versions
# use `--permission-mode bypassPermissions` instead of the flag below.
CLAUDE_PERM_FLAGS="--dangerously-skip-permissions"

log_line() {
  printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"
}

has_draft_frontmatter() {
  awk 'BEGIN{in_fm=0}
       NR==1 && $0=="---"{in_fm=1; next}
       in_fm && $0=="---"{exit}
       in_fm && /^status:[[:space:]]*draft[[:space:]]*$/{print "Y"; exit}
       NR>40{exit}' "$1" | grep -q Y
}

classify_op() {
  local path="$1" sha="$2"
  if grep -qF "| $path sha:$sha" /vault/log.md 2>/dev/null; then
    printf ''
    return
  fi
  if grep -qF "| $path sha:" /vault/log.md 2>/dev/null; then
    printf 'reingest'
    return
  fi
  printf 'new'
}

build_pending_list() {
  find /vault/raw -type f \
    -not -path '/vault/raw/assets/*' \
    -not -name '.DS_Store' \
    -not -name '.gitkeep' \
    -print0 \
  | while IFS= read -r -d '' path; do
      # GNU stat only (container-only execution)
      mtime=$(stat -c %Y "$path")
      [ $(( $(date +%s) - mtime )) -lt "$STABILITY_SECS" ] && continue

      size=$(stat -c %s "$path")
      [ "$size" -lt 50 ] && continue

      case "$path" in
        *.md|*.markdown)
          if has_draft_frontmatter "$path"; then continue; fi
          ;;
      esac

      sha=$(sha256sum "$path" | cut -c1-12)
      relpath="${path#/vault/}"
      op=$(classify_op "$relpath" "$sha")
      [ -z "$op" ] && continue

      printf '%s\t%s\t%s\t%s\n' "$relpath" "$sha" "$size" "$op"
    done
}

# NUL-delimited output so consumer reads whole batches via `read -r -d ''`.
# printf "%c", 0 (not "\0") — mawk silently drops \0; %c,0 works in mawk+gawk.
build_batches() {
  local budget="$1"
  awk -v budget="$budget" '
    function flush() {
      if (have_lines) { printf "%s%c", buf, 0 }
      buf=""; have_lines=0; acc=0
    }
    {
      size = $3 + 0
      # Oversize file: flush current, emit it alone, reset.
      if (size > budget && have_lines) flush()
      if (buf) buf = buf "\n" $0; else buf = $0
      have_lines = 1
      acc += size
      if (acc >= budget) flush()
    }
    END { flush() }
  '
}

verify_and_patch_log() {
  local batch="$1" had_miss=0
  local path sha size op
  while IFS=$'\t' read -r path sha size op; do
    [ -z "$path" ] && continue
    if grep -qF "| $path sha:$sha" /vault/log.md; then continue; fi
    # Look for an unsuffixed log line for this exact path.
    if grep -qE "^## \[.*\] (ingest|re-ingest) \| $(printf '%s' "$path" | sed 's/[]\\/&.*^$[]/\\&/g')$" /vault/log.md; then
      awk -v path="$path" -v sfx=" sha:$sha" '
        {
          if (match($0, "^## \\[.*\\] (ingest|re-ingest) \\| " path "$")) {
            last = NR
          }
          lines[NR] = $0
        }
        END {
          for (i = 1; i <= NR; i++) {
            if (i == last) print lines[i] sfx
            else print lines[i]
          }
        }
      ' /vault/log.md > /vault/log.md.tmp && mv /vault/log.md.tmp /vault/log.md
      had_miss=1
    else
      log_line "WARNING: no log entry for $path after claude exit 0; will reprocess next poll"
    fi
  done <<< "$batch"
  [ "$had_miss" = "1" ] && return 1 || return 0
}

run_claude_on_batch() {
  local batch="$1"
  [ -z "$batch" ] && { log_line "empty batch; skipping"; return 0; }

  local files_md="" path sha size op
  while IFS=$'\t' read -r path sha size op; do
    [ -z "$path" ] && continue
    files_md+="- \`${path}\` (sha:${sha}, op:${op})"$'\n'
  done <<< "$batch"

  if [ -z "$files_md" ]; then
    log_line "batch produced no parseable entries; skipping"
    return 0
  fi

  local prompt
  prompt="$(cat <<EOF
Run the ingest-source skill NOW on exactly these files, in this order. Do not
scan raw/ for other files — use only this list:

${files_md}
CONTRACT (must follow exactly, no exceptions):

1. For each file: op:new means normal ingest; op:reingest means rewrite the
   EXISTING wiki/sources page (do not create a new dated file — find the source
   page whose frontmatter sources: list includes this raw path and update in place)
   and revise dependent entity/concept pages.

2. Every log entry you append must end with a space then sha:<prefix>, where
   <prefix> is exactly the 12-char prefix provided above for that file. Example:
     ## [YYYY-MM-DD] ingest | raw/foo.md sha:abc123def456
     ## [YYYY-MM-DD] re-ingest | raw/bar.md sha:789abc012345
   The auto-ingest loop reads this suffix for dedup; omitting it causes infinite
   re-processing.

3. Follow all normal skill steps (git pull, group attachments, write wiki pages,
   update index.md, append log.md, commit, push).
EOF
  )"

  # claude -p discovers CLAUDE.md + skills from cwd; /agent is the agent root.
  cd /agent
  local rc
  # shellcheck disable=SC2086  # CLAUDE_PERM_FLAGS intentionally word-splits (one or two tokens)
  claude -p "$prompt" $CLAUDE_PERM_FLAGS
  rc=$?
  [ $rc -ne 0 ] && return $rc

  verify_and_patch_log "$batch" || log_line "WARNING: post-check patched one or more log entries"
  return 0
}

# One-shot first-run backfill of sha: suffixes on existing log entries.
/opt/autoblog/bin/migrate-log-sha.sh || log_line "migration failed (non-fatal)"

in_backoff=0

while true; do
  if [ "$ENABLED" != "1" ]; then
    sleep "$POLL_INTERVAL"
    continue
  fi

  if [ "$in_backoff" = "1" ]; then
    next_sleep="$FAILURE_BACKOFF_SECS"
  else
    next_sleep="$POLL_INTERVAL"
  fi

  if ! git -C /vault pull --rebase --quiet; then
    log_line "pull failed; sleeping $FAILURE_BACKOFF_SECS"
    in_backoff=1
    sleep "$FAILURE_BACKOFF_SECS"
    continue
  fi

  pending="$(build_pending_list)"
  if [ -z "$pending" ]; then
    in_backoff=0
    sleep "$next_sleep"
    continue
  fi

  hit_cap=0
  failed=0
  batch_count=0
  while IFS= read -r -d '' batch; do
    [ -z "$batch" ] && continue
    batch_count=$(( batch_count + 1 ))
    if [ "$batch_count" -gt "$MAX_BATCHES_PER_WAKE" ]; then
      log_line "hit MAX_BATCHES_PER_WAKE=$MAX_BATCHES_PER_WAKE; remainder deferred"
      hit_cap=1
      break
    fi
    if ! run_claude_on_batch "$batch"; then
      log_line "batch failed; entering 1-hour backoff"
      failed=1
      break
    fi
  done < <(build_batches "$BATCH_BYTES" <<< "$pending")

  if [ "$failed" = "1" ]; then
    in_backoff=1
    sleep "$FAILURE_BACKOFF_SECS"
  else
    in_backoff=0
    # When capped but more pending, shorten next sleep to drain the queue.
    if [ "$hit_cap" = "1" ] && [ "$POLL_INTERVAL" -gt 60 ]; then
      sleep 60
    else
      sleep "$POLL_INTERVAL"
    fi
  fi
done
