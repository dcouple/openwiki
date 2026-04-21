#!/bin/bash
set -euo pipefail

# openwiki interactive setup.
# Collects credentials, writes .env, and brings the stack up.
# Run from the repo root:  bash scripts/setup.sh

cd "$(dirname "$0")/.."

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
rule() { printf '\033[2m----------------------------------------\033[0m\n'; }

bold "openwiki setup"
rule
cat <<'EOF'
This script configures openwiki for first run. It will:

  1. Collect your SSH public key.
  2. Write .env.
  3. Start the Docker stack — on first boot this seeds a fresh
     Obsidian vault and a fresh Astro website into Docker volumes
     (3–10 minutes for npm install + initial build).

Both the vault and site are managed as git repos inside the container.
The agent commits and pushes edits to those repos as it works. You
sync your devices in by pointing the Obsidian Git plugin at openwiki
(instructions printed at the end).

You'll authenticate Claude after the stack is up by running `/login`
inside the agent — no API key needed here.

EOF

command -v docker >/dev/null || { echo "ERROR: install Docker first." >&2; exit 1; }
docker compose version >/dev/null || { echo "ERROR: install the docker compose plugin." >&2; exit 1; }

if [ -f .env ]; then
  echo ".env already exists."
  read -r -p "Overwrite it? [y/N] " reply
  case "${reply:-}" in
    y|Y|yes|YES) ;;
    *) echo "Aborted. Nothing changed."; exit 0 ;;
  esac
  backup=".env.backup.$(date +%Y%m%d-%H%M%S)"
  cp .env "$backup"
  echo "Existing .env backed up to $backup"
fi

# ---------- SSH public key ----------
echo
bold "SSH key"
echo "You'll SSH into the agent container with the matching private key."

ssh_default=""
ssh_default_path=""
for candidate in "$HOME/.ssh/id_ed25519.pub" "$HOME/.ssh/id_rsa.pub"; do
  if [ -f "$candidate" ]; then
    ssh_default=$(cat "$candidate")
    ssh_default_path="$candidate"
    break
  fi
done

if [ -n "$ssh_default" ]; then
  echo "Found: $ssh_default_path"
  echo "  $ssh_default"
  read -r -p "Use this key? [Y/n] " reply
  case "${reply:-}" in
    n|N|no|NO) read -r -p "Paste SSH public key: " ssh_public_key ;;
    *)         ssh_public_key="$ssh_default" ;;
  esac
else
  echo "No SSH public key found in ~/.ssh. Generate one with:"
  echo "  ssh-keygen -t ed25519 -C \"$USER@$(hostname -s)\""
  read -r -p "Paste SSH public key: " ssh_public_key
fi

if [ -z "${ssh_public_key// }" ]; then
  echo "ERROR: SSH public key is required." >&2
  exit 1
fi

# ---------- Write .env ----------
echo
bold "Writing .env"

escaped_key=${ssh_public_key//\"/\\\"}

cat > .env <<EOF
# --- required ---
SSH_PUBLIC_KEY="$escaped_key"
TIMEZONE=America/Los_Angeles

# --- Claude Code auth ---
# Leave blank to /login with Claude Pro/Max from inside the agent.
# Set to an API key from console.anthropic.com to authenticate via API instead.
ANTHROPIC_API_KEY=

# --- Phase 1 defaults (laptop sandbox) ---
DOMAIN=localhost
SSH_BIND=127.0.0.1
DEV_BIND=127.0.0.1
CADDY_BIND=127.0.0.1
CADDY_HTTP_PORT=8080
CADDY_HTTPS_PORT=8443

# --- Phase 2 overrides (uncomment on VPS) ---
# DOMAIN=your-real-domain.com
# SSH_BIND=0.0.0.0
# CADDY_BIND=0.0.0.0
# CADDY_HTTP_PORT=80
# CADDY_HTTPS_PORT=443
EOF

echo "  wrote .env"

# ---------- Start ----------
echo
read -r -p "Start openwiki now? [Y/n] " reply
case "${reply:-}" in
  n|N|no|NO)
    echo
    echo "To start later, run:  docker compose up -d --wait"
    started=0
    ;;
  *)
    echo
    echo "Starting… first boot runs npm install + an initial Astro build"
    echo "(3–10 minutes). Tail logs with:  docker compose logs -f"
    echo
    docker compose up -d --wait
    started=1
    ;;
esac

# ---------- Next steps ----------
echo
bold "Next steps"
rule
cat <<EOF
Your openwiki is${started:+ up}${started:- configured}. The stack provides:

  Agent:  ./bin/autoblog         (SSH + tmux + claude)
  Dev:    http://localhost:4321  (site preview with drafts)
  Prod:   http://localhost:8080  (published pages only)

To use your vault from Obsidian on your laptop or phone:

  1. Install Obsidian from https://obsidian.md.
  2. Open Obsidian → "Open folder as vault" → pick a new empty folder.
  3. Settings → Community plugins → turn on, install "Obsidian Git".
  4. In Obsidian Git settings, set the remote to openwiki's bare repo:
        ssh://autoblog@localhost:2222/vault-remote.git
     (Use the SSH key you configured above.)
  5. Run "Obsidian Git: Pull" from the command palette.

Your vault and site live in Docker volumes, managed as git repos.
The agent commits on your behalf as it curates the wiki and site.
EOF
