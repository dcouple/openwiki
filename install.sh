#!/bin/bash
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/dcouple/openwiki/main/install.sh -o /tmp/openwiki-install.sh
#   sudo bash /tmp/openwiki-install.sh
# Or pin a version:
#   sudo VERSION=v0.1.0 bash /tmp/openwiki-install.sh
# Or to reconfigure .env in place:
#   sudo RECONFIGURE=1 bash /tmp/openwiki-install.sh
set -euo pipefail

VERSION="${VERSION:-latest}"
IMAGE="ghcr.io/dcouple/openwiki:$VERSION"
INSTALL_DIR="${INSTALL_DIR:-/opt/openwiki}"

die()  { echo "ERROR: $*" >&2; exit 1; }
warn() { echo "WARN:  $*" >&2; }

require_root() { [ "$EUID" -eq 0 ] || die "run with sudo."; }

detect_os() {
  [ -f /etc/os-release ] || die "unsupported OS (no /etc/os-release)"
  # shellcheck disable=SC1091
  . /etc/os-release
  case "${ID:-}" in
    debian|ubuntu) ;;
    *) die "tested only on Debian 12 / Ubuntu 22.04+. Found: ${ID:-?}" ;;
  esac
}

detect_sshd_port() {
  local p
  p=$(sshd -T 2>/dev/null | awk '$1 == "port" { print $2; exit }')
  echo "${p:-22}"
}

install_docker() {
  if command -v docker >/dev/null && docker compose version >/dev/null 2>&1; then return; fi
  echo "[docker] installing via get.docker.com"
  curl -fsSL https://get.docker.com | sh
}

install_jq() { command -v jq >/dev/null 2>&1 || apt-get install -y jq; }

configure_firewall() {
  command -v ufw >/dev/null || apt-get install -y ufw
  local sshd_port
  sshd_port=$(detect_sshd_port)
  ufw --force default deny incoming
  ufw --force default allow outgoing
  ufw allow "$sshd_port"/tcp comment 'host sshd'
  [ "$sshd_port" != "22" ] && ufw allow 22/tcp   comment 'host sshd fallback'
  ufw allow 2222/tcp comment 'openwiki agent ssh'
  ufw allow 80/tcp   comment 'caddy http / acme'
  ufw allow 443/tcp  comment 'caddy https'
  ufw --force enable
}

configure_fail2ban() {
  command -v fail2ban-client >/dev/null || apt-get install -y fail2ban
  systemctl enable --now fail2ban
}

is_legacy_install() {
  [ -d "$INSTALL_DIR/.git" ] \
    || [ -f "$INSTALL_DIR/autoblog/Dockerfile" ] \
    || { [ -L /usr/local/bin/openwiki ] && readlink -f /usr/local/bin/openwiki | grep -q "/bin/openwiki$"; }
}

migrate_legacy() {
  echo
  echo "==== legacy git-clone install detected at $INSTALL_DIR ===="
  echo "About to:"
  echo "  1. Back up all volumes to $INSTALL_DIR/backups/legacy-<timestamp>.tar.gz"
  echo "  2. Stop the running stack (volumes preserved on the docker engine)"
  echo "  3. Rename $INSTALL_DIR -> $INSTALL_DIR.legacy-<timestamp>"
  echo "  4. Install fresh at $INSTALL_DIR"
  echo "  5. The same named volumes will be reattached, so content is preserved"
  echo
  read -r -p "Proceed? [y/N] " reply < /dev/tty
  [ "${reply:-N}" = "y" ] || die "migration aborted"

  (cd "$INSTALL_DIR" && ./bin/openwiki backup) || warn "backup step failed (continuing)"
  (cd "$INSTALL_DIR" && docker compose down)   || warn "docker compose down failed (continuing)"

  local ts
  ts=$(date +%Y%m%d-%H%M%S)
  mv "$INSTALL_DIR" "$INSTALL_DIR.legacy-$ts"
  echo "[migrate] moved old install to $INSTALL_DIR.legacy-$ts"
}

extract_image_config() {
  docker pull "$IMAGE"
  local cid
  cid=$(docker create "$IMAGE")
  # shellcheck disable=SC2064
  trap "docker rm -f '$cid' >/dev/null 2>&1 || true" EXIT
  mkdir -p "$INSTALL_DIR"
  docker cp "$cid:/opt/openwiki/compose.yml"        "$INSTALL_DIR/compose.yml"
  docker cp "$cid:/opt/openwiki/Caddyfile.template" "$INSTALL_DIR/Caddyfile.template"
  docker cp "$cid:/opt/openwiki/openwiki"           "$INSTALL_DIR/openwiki"
  docker rm -f "$cid" >/dev/null
  trap - EXIT
  chmod +x "$INSTALL_DIR/openwiki"
  ln -sf "$INSTALL_DIR/openwiki" /usr/local/bin/openwiki
}

# Render $INSTALL_DIR/Caddyfile from $INSTALL_DIR/Caddyfile.template.
# Empty or "localhost" domain => HTTP-only block on :80 (no ACME attempts).
# Real domain => __DOMAIN__ substitution; Caddy handles auto-TLS on boot.
# When ACME_STAGING=1 is in the environment, prepend a global `acme_ca` directive
# pointing Caddy at LE staging — untrusted certs but loose rate limits, useful
# while iterating on DNS. Only applies on the non-localhost path.
render_caddyfile() {
  local domain="$1"
  local template="$INSTALL_DIR/Caddyfile.template"
  local out="$INSTALL_DIR/Caddyfile"
  case "$domain" in
    ""|localhost)
      cat > "$out" <<'EOF'
:80 {
    root * /srv/site/prod/dist
    file_server
    try_files {path} {path}/ /index.html
    encode gzip
    header / Cache-Control "public, max-age=300"
}
EOF
      ;;
    *)
      {
        if [ "${ACME_STAGING:-0}" = "1" ]; then
          echo "{"
          echo "    acme_ca https://acme-staging-v02.api.letsencrypt.org/directory"
          echo "}"
          echo
        fi
        sed "s/__DOMAIN__/$domain/g" "$template"
      } > "$out"
      ;;
  esac
  echo "[install] rendered $out for DOMAIN=${domain:-localhost}${ACME_STAGING:+ (ACME staging)}"
}

# DNS precheck: compare the domain's A record to this VM's public IP and,
# on mismatch, let the operator pick LE staging / HTTP-only / continue.
# Sets $domain_to_use (caller must `local domain_to_use=""` it).
# Also sets ACME_STAGING=1 in the caller's environment on choice [s], which
# render_caddyfile then honors.
dns_precheck() {
  local domain="$1"
  if [ -z "$domain" ] || [ "$domain" = "localhost" ]; then
    return 0
  fi

  local vm_ip dns_ip choice
  vm_ip=$(curl -s4 https://api.ipify.org || echo "unknown")
  dns_ip=$(dig +short "$domain" A | tail -n1)

  if [ -z "$dns_ip" ]; then
    warn "DNS record for $domain does not resolve."
  elif [ "$dns_ip" != "$vm_ip" ]; then
    warn "DNS $domain -> $dns_ip, but this VM's public IP appears to be $vm_ip."
  else
    echo "[dns] $domain -> $dns_ip (matches VM IP)"
    return 0
  fi

  echo
  echo "Caddy will try Let's Encrypt on first boot. If DNS is wrong, LE rate-limits"
  echo "this hostname for ~1 hour. Options:"
  echo "  [s] use LE STAGING (untrusted certs, loose limits — safe for iterating)"
  echo "  [h] use HTTP only (skip ACME entirely; rerun install.sh when DNS is ready)"
  echo "  [c] continue anyway with LE production (only if you're sure DNS is right)"
  read -r -p "Choice [s/h/c]: " choice < /dev/tty
  case "$choice" in
    s) export ACME_STAGING=1; domain_to_use="$domain" ;;
    h) domain_to_use="" ;;  # falls back to :80 rendering
    c) domain_to_use="$domain" ;;
    *) die "aborted" ;;
  esac
}

prompt_env() {
  if [ -f "$INSTALL_DIR/.env" ] && [ "${RECONFIGURE:-0}" != "1" ]; then
    echo "[.env] present — skipping prompts. Set RECONFIGURE=1 to re-enter."
    return
  fi

  echo
  echo "==== openwiki interactive setup ===="
  local domain ssh_key anthropic
  local domain_to_use=""
  read -r -p "Domain (blank for HTTP-only at the IP): "        domain    < /dev/tty
  read -r -p "SSH public key (paste, one line): "              ssh_key   < /dev/tty
  echo
  echo "Claude Code auth:"
  echo "  (A) blank -> use Pro/Max subscription via /login on first boot"
  echo "  (B) paste an Anthropic API key"
  read -r -p "ANTHROPIC_API_KEY (or blank for A): "            anthropic < /dev/tty

  [ -n "$domain" ] && dns_precheck "$domain"

  # Always re-render Caddyfile to match whatever domain we ended up with.
  render_caddyfile "${domain_to_use:-$domain}"

  cat > "$INSTALL_DIR/.env" <<EOF
COMPOSE_PROJECT_NAME=openwiki
SSH_PUBLIC_KEY="$ssh_key"
TIMEZONE=UTC
ANTHROPIC_API_KEY=$anthropic
DOMAIN=${domain_to_use:-${domain:-localhost}}
SSH_BIND=0.0.0.0
DEV_BIND=127.0.0.1
CADDY_BIND=0.0.0.0
CADDY_HTTP_PORT=80
CADDY_HTTPS_PORT=443
EOF
  # Persist ACME_STAGING so re-renders (e.g. `openwiki set-domain`) remember it.
  [ "${ACME_STAGING:-0}" = "1" ] && echo "ACME_STAGING=1" >> "$INSTALL_DIR/.env"
  # Explicit perms — do NOT rely on umask. .env holds an API key.
  chmod 600 "$INSTALL_DIR/.env"
  chown root:root "$INSTALL_DIR/.env"
}

start_stack() {
  cd "$INSTALL_DIR"
  docker compose up -d --wait
  /usr/local/bin/openwiki status
}

main() {
  require_root
  detect_os
  is_legacy_install && migrate_legacy
  install_docker
  install_jq
  configure_firewall
  configure_fail2ban
  extract_image_config
  prompt_env
  start_stack
}

main "$@"
