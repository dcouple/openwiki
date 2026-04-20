#!/bin/bash
set -euo pipefail

command -v docker >/dev/null || { echo "ERROR: install Docker first."; exit 1; }
docker compose version >/dev/null || { echo "ERROR: install docker compose plugin."; exit 1; }

if [ ! -f .env ]; then
  cp .env.example .env
  echo ".env created from .env.example. Edit it to set:"
  echo "  - SSH_PUBLIC_KEY  (required)"
  echo "  - ANTHROPIC_API_KEY  (optional; leave blank to use a Claude Pro/Max login)"
  echo "Then re-run this script."
  exit 0
fi

echo "Starting autoblog. First boot runs npm install + an initial Astro build,"
echo "which takes 3-10 minutes. Tail logs in another terminal with:"
echo "  docker compose logs -f"
echo

docker compose up -d --wait

cat <<'EOF'

autoblog is up.
  Agent:  ./bin/autoblog         (SSH + tmux + claude)
  Dev:    http://localhost:4321  (all content, including drafts)
  Prod:   http://localhost:8080  (published pages only)

If the prod URL is held by another app, change CADDY_HTTP_PORT in .env,
then run: docker compose up -d
EOF
