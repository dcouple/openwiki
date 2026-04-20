#!/bin/bash
set -euo pipefail

TEMPLATES=/opt/autoblog/templates

# Seed /agent on first boot
if [ ! -f /agent/CLAUDE.md ]; then
  echo "[bootstrap] seeding /agent"
  cp -r "$TEMPLATES/agent-template/." /agent/
  chown -R autoblog:autoblog /agent
fi

# Seed /site + create bare repo + two worktrees on first boot
if [ ! -d /site/repo.git ]; then
  echo "[bootstrap] seeding /site (bare repo + prod/dev worktrees)"

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

  chown -R autoblog:autoblog /site
fi

# Generate SSH host keys if missing (idempotent — ssh-keygen -A won't overwrite)
ssh-keygen -A

# Inject authorized_keys from env (re-written every boot so env updates take effect)
if [ -n "${SSH_PUBLIC_KEY:-}" ]; then
  mkdir -p /home/autoblog/.ssh
  echo "$SSH_PUBLIC_KEY" > /home/autoblog/.ssh/authorized_keys
  chmod 700 /home/autoblog/.ssh
  chmod 600 /home/autoblog/.ssh/authorized_keys
  chown -R autoblog:autoblog /home/autoblog/.ssh
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
chown -R autoblog:autoblog /home/autoblog/.ssh

# Named volume mounts /home/autoblog/.claude root-owned on first boot;
# Claude CLI needs to write there (e.g. session-env/).
mkdir -p /home/autoblog/.claude
chown -R autoblog:autoblog /home/autoblog/.claude

# Readiness marker for the healthcheck
touch /var/run/autoblog-ready
echo "[bootstrap] ready"
