#!/bin/bash
# One-shot VPS provisioning for autoblog. Idempotent — safe to re-run.
#
# Usage (from the cloned repo root on a fresh Debian 12 / Ubuntu 22.04+ VPS):
#   sudo bash scripts/provision-vps.sh
#
# What it does:
#   1. Installs Docker Engine + compose plugin (official get.docker.com)
#   2. Installs & configures ufw (allow 22, 2222, 80, 443; deny rest)
#   3. Installs & enables fail2ban (host sshd jail)
#   4. Seeds .env from .env.example if missing, then stops for you to edit
#
# After editing .env, re-run this script OR run ./scripts/install.sh directly.

set -euo pipefail

require_root() {
  if [ "$EUID" -ne 0 ]; then
    echo "ERROR: run with sudo (needs to install packages, edit firewall, start services)."
    exit 1
  fi
}

require_repo_root() {
  if [ ! -f .env.example ] || [ ! -f compose.yml ]; then
    echo "ERROR: run from the autoblog repo root (.env.example and compose.yml not found here)."
    exit 1
  fi
}

detect_os() {
  if [ ! -f /etc/os-release ]; then
    echo "ERROR: /etc/os-release missing — unsupported OS."
    exit 1
  fi
  # shellcheck disable=SC1091
  . /etc/os-release
  case "${ID:-}" in
    debian|ubuntu) echo "OS: ${PRETTY_NAME:-$ID}" ;;
    *)
      echo "ERROR: tested only on Debian 12 / Ubuntu 22.04+. Found: ${ID:-unknown} ${VERSION_ID:-}"
      exit 1
      ;;
  esac
}

install_docker() {
  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    echo "[docker] already installed — skipping."
    return
  fi
  echo "[docker] installing via get.docker.com..."
  curl -fsSL https://get.docker.com | sh
  if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
    usermod -aG docker "$SUDO_USER"
    echo "[docker] added $SUDO_USER to docker group (effective after logout/login)."
  fi
}

configure_firewall() {
  if ! command -v ufw >/dev/null 2>&1; then
    apt-get update
    apt-get install -y ufw
  fi
  ufw --force default deny incoming
  ufw --force default allow outgoing
  ufw allow 22/tcp    comment 'host sshd (emergency)'
  ufw allow 2222/tcp  comment 'container sshd (primary)'
  ufw allow 80/tcp    comment 'Caddy HTTP'
  ufw allow 443/tcp   comment 'Caddy HTTPS'
  ufw --force enable
  echo "[ufw] configured:"
  ufw status verbose
}

configure_fail2ban() {
  if ! command -v fail2ban-client >/dev/null 2>&1; then
    apt-get install -y fail2ban
  fi
  systemctl enable --now fail2ban
  echo "[fail2ban] active:"
  fail2ban-client status
}

seed_env() {
  if [ -f .env ]; then
    echo "[.env] exists — leaving untouched."
    return 1
  fi
  cp .env.example .env
  cat <<'MSG'
[.env] created from .env.example. Edit it to set:
  - ANTHROPIC_API_KEY
  - SSH_PUBLIC_KEY (one line per device, comma-less)
  - DOMAIN=your-real-domain.com
  - Uncomment the Phase 2 overrides:
      SSH_BIND=0.0.0.0
      CADDY_BIND=0.0.0.0
      CADDY_HTTP_PORT=80
      CADDY_HTTPS_PORT=443

Then run:  ./scripts/install.sh
MSG
  return 0
}

main() {
  require_root
  require_repo_root
  detect_os
  install_docker
  configure_firewall
  configure_fail2ban

  if seed_env; then
    exit 0
  fi

  echo
  echo "Provisioning complete. .env already present; not starting the stack here —"
  echo "run ./scripts/install.sh when you're ready."
}

main "$@"
