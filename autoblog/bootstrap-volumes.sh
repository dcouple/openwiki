#!/bin/bash
set -euo pipefail

TEMPLATES=/opt/autoblog/templates

# Seed /agent on first boot
if [ ! -f /agent/CLAUDE.md ]; then
  echo "[bootstrap] seeding /agent"
  cp -r "$TEMPLATES/agent-template/." /agent/
  chown -R autoblog:autoblog /agent
fi

# Seed /srv/static on first boot (placeholder page for 1a; replaced in 1b)
if [ ! -f /srv/static/index.html ]; then
  echo "[bootstrap] seeding /srv/static"
  cp -r "$TEMPLATES/static-template/." /srv/static/
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

# Deliver ANTHROPIC_API_KEY to login shells via ~/.ssh/environment.
# sshd reads this when PermitUserEnvironment yes. Works for both interactive
# and non-interactive SSH; .bashrc does not.
if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
  mkdir -p /home/autoblog/.ssh
  echo "ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}" > /home/autoblog/.ssh/environment
  chmod 600 /home/autoblog/.ssh/environment
  chown -R autoblog:autoblog /home/autoblog/.ssh
fi

# Readiness marker for the healthcheck
touch /var/run/autoblog-ready
echo "[bootstrap] ready"
