#!/bin/bash
set -euo pipefail

TEMPLATES=/opt/autoblog/templates

# Bootstrap runs as root; volume mountpoints are owned by `autoblog` once chowned.
# Git 2.35+ refuses ops across uid boundaries ("dubious ownership") unless told the
# dir is trusted. In this container everything is trusted — declare that globally
# for root so every git call in bootstrap works regardless of volume ownership.
git config --global --add safe.directory '*'

# Seed /agent on first boot.
# Idempotency: CLAUDE.md is in the template root, so its presence = successful cp.
if [ ! -f /agent/CLAUDE.md ]; then
  echo "[bootstrap] seeding /agent"
  cp -r "$TEMPLATES/agent-template/." /agent/
fi

# Seed /site on first boot.
# Idempotency: /site/prod/dist is the last artifact produced (post npm install + build),
# so its presence = full seed completed. An earlier crash leaves it absent and we reseed.
if [ ! -d /site/prod/dist ]; then
  echo "[bootstrap] seeding /site (bare repo + prod/dev worktrees)"

  # Wipe any partial state from a prior crashed boot
  find /site -mindepth 1 -delete 2>/dev/null || true

  rm -rf /tmp/site-seed
  mkdir -p /tmp/site-seed
  cp -r "$TEMPLATES/site-template/." /tmp/site-seed/
  cd /tmp/site-seed
  git init -b main
  git add .
  git -c user.email=agent@autoblog -c user.name="autoblog agent" commit -m "initial site seed"

  git init --bare -b main /site/repo.git
  git push /site/repo.git main
  rm -rf /tmp/site-seed

  git -C /site/repo.git worktree add /site/prod main
  git -C /site/repo.git worktree add -b dev /site/dev main

  echo "[bootstrap] npm install in /site/dev (first run — several minutes)…"
  (cd /site/dev && npm install) 2>&1 | sed 's/^/  [dev] /'
  echo "[bootstrap] npm install in /site/prod…"
  (cd /site/prod && npm install) 2>&1 | sed 's/^/  [prod] /'

  echo "[bootstrap] initial astro build in /site/prod…"
  (cd /site/prod && npm run build) 2>&1 | sed 's/^/  [build] /'
fi

# Seed /vault-remote.git (bare) + /vault (working clone) on first boot.
# Idempotency: `git init --bare` creates HEAD *before* any commit is pushed, so
# checking `[ ! -f HEAD ]` is not sufficient — a crash between init and push leaves
# HEAD present with an unborn branch, and the old check would then skip reseeding.
# `git rev-parse --verify HEAD` only succeeds when the branch has a real commit.
if ! git -C /vault-remote.git rev-parse --verify HEAD >/dev/null 2>&1; then
  echo "[bootstrap] seeding /vault-remote.git + /vault"

  find /vault-remote.git -mindepth 1 -delete 2>/dev/null || true
  find /vault -mindepth 1 -delete 2>/dev/null || true

  rm -rf /tmp/vault-seed
  mkdir -p /tmp/vault-seed
  cp -r "$TEMPLATES/vault-template/." /tmp/vault-seed/
  cd /tmp/vault-seed
  git init -b main
  git add .
  git -c user.email=agent@autoblog -c user.name="autoblog agent" commit -m "initial vault seed"

  git init --bare -b main /vault-remote.git
  git push /vault-remote.git main
  rm -rf /tmp/vault-seed

  git clone /vault-remote.git /vault

  git -C /vault config user.email "agent@autoblog"
  git -C /vault config user.name "autoblog agent"
fi

# Generate SSH host keys if missing (idempotent — ssh-keygen -A won't overwrite)
ssh-keygen -A

# Inject authorized_keys from env (re-written every boot so env updates take effect)
if [ -n "${SSH_PUBLIC_KEY:-}" ]; then
  mkdir -p /home/autoblog/.ssh
  echo "$SSH_PUBLIC_KEY" > /home/autoblog/.ssh/authorized_keys
  chmod 700 /home/autoblog/.ssh
  chmod 600 /home/autoblog/.ssh/authorized_keys
fi

# Deliver env to login shells via ~/.ssh/environment.
# sshd reads this when PermitUserEnvironment yes. Works for both interactive
# and non-interactive SSH; .bashrc does not. SSH also does not forward LANG
# from the client, so we set it here so Claude Code's unicode UI renders.
mkdir -p /home/autoblog/.ssh
{
  [ -n "${ANTHROPIC_API_KEY:-}" ] && echo "ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}"
  echo "LANG=C.UTF-8"
  echo "LC_ALL=C.UTF-8"
} > /home/autoblog/.ssh/environment
chmod 600 /home/autoblog/.ssh/environment

# Named volumes mount root-owned; a partial/crashed seed can also leave root-owned
# files inside them. Chown unconditionally at the end of every boot so the autoblog
# user always has read/write on its paths — this is the failsafe the idempotency
# checks above rely on.
mkdir -p /home/autoblog/.claude
chown -R autoblog:autoblog \
  /agent /site /vault /vault-remote.git \
  /home/autoblog/.claude /home/autoblog/.ssh

# Readiness marker for the healthcheck
touch /var/run/autoblog-ready
echo "[bootstrap] ready"
