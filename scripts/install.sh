#!/bin/bash
set -euo pipefail

command -v docker >/dev/null || { echo "ERROR: install Docker first."; exit 1; }
docker compose version >/dev/null || { echo "ERROR: install docker compose plugin."; exit 1; }

if [ ! -f .env ]; then
  cp .env.example .env
  echo ".env created from .env.example — edit it to set ANTHROPIC_API_KEY and SSH_PUBLIC_KEY, then re-run this script."
  exit 0
fi

docker compose up -d --wait

echo
echo "autoblog is up."
echo "  SSH:  ssh -p 2222 autoblog@localhost"
echo "  Prod: http://localhost:8080  (placeholder in 1a; real site in 1b)"
