#!/bin/bash
# Safe code update for an autoblog VPS. Idempotent — safe to re-run.
#
# Usage (from the cloned repo root on the VPS; repo is at /opt/autoblog):
#   sudo bash scripts/update.sh
#
# What it does:
#   1. Refuses to run if tracked files are dirty (won't touch your edits)
#   2. `git pull --ff-only` on the current branch (refuses divergence)
#   3. `docker compose up -d --build` to pick up new code
#
# Your vault, site, and agent data live in Docker named volumes and are
# NOT touched by this script. The image's bootstrap-volumes.sh only seeds
# empty volumes, so a rebuild cannot overwrite your content.

set -euo pipefail

require_root() {
  if [ "$EUID" -ne 0 ]; then
    echo "ERROR: run with sudo (repo at /opt/autoblog is owned by root; also needed for docker)."
    exit 1
  fi
}

require_repo_root() {
  if [ ! -f .env.example ] || [ ! -f compose.yml ]; then
    echo "ERROR: run from the autoblog repo root (.env.example and compose.yml not found here)."
    exit 1
  fi
}

refuse_dirty_tree() {
  # Only consider tracked files. `.env` and other gitignored files must NOT
  # block the update. `--untracked-files=no` + `--porcelain` emits one line
  # per modified/staged tracked file.
  local dirty
  dirty=$(git status --porcelain --untracked-files=no)
  if [ -n "$dirty" ]; then
    echo "ERROR: uncommitted changes to tracked files:"
    echo "$dirty" | sed 's/^/  /'
    echo
    echo "Commit, stash, or revert these before updating."
    exit 1
  fi
}

pull_fast_forward() {
  local branch
  branch=$(git rev-parse --abbrev-ref HEAD)
  echo "[git] pulling $branch from origin (fast-forward only)"
  # --ff-only exits non-zero if HEAD has diverged. That is correct: we do NOT
  # want to auto-rebase or auto-merge on a production host. --ff-only already
  # fetches; no separate `git fetch` needed.
  if ! git pull --ff-only; then
    echo
    echo "ERROR: git pull could not fast-forward."
    echo "Branch '$branch' has diverged from origin. Resolve manually, then re-run this script."
    exit 1
  fi
}

rebuild_stack() {
  echo "[docker] rebuilding and restarting the stack..."
  docker compose up -d --build
}

post_success_message() {
  cat <<'EOF'

Update complete. Your vault, site, and agent data are untouched.

To pull shipped skill/prompt changes into your live agent, SSH into the
container and paste this sentence at the agent prompt (one line):

  Run the procedure in /opt/autoblog/templates/agent-template/.claude/skills/sync-upstream.md

After the first run, the sync-upstream skill lives at /agent/.claude/skills/,
and future syncs are just: "sync upstream".

Note: sshd_config changes in new images are shadowed by the autoblog_ssh volume
and will not take effect on existing installs. (host keys live in that volume.)
EOF
}

main() {
  require_root
  require_repo_root
  refuse_dirty_tree
  pull_fast_forward
  rebuild_stack
  post_success_message
}

main "$@"
